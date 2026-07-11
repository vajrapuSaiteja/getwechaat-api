-- v0.5.0 migration: WhatsApp bot sessions + service functions + public invoice links

-- Conversation state for the bot (one row per vendor phone)
create table if not exists bot_sessions (
  phone      text primary key,          -- vendor phone, last-10-digits normalized
  seller_id  uuid references sellers(id) on delete cascade,
  state      text not null default 'idle',
  draft      jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table bot_sessions enable row level security;
-- no policies: only the service role (bot server) touches this table

-- Public shareable token on invoices
alter table invoices add column if not exists public_token uuid not null default gen_random_uuid();
create unique index if not exists idx_invoices_public_token on invoices(public_token);

-- Invoice creation on behalf of a seller (bot server only, service role)
create or replace function create_invoice_by_seller(
  p_seller uuid,
  p_customer_name text,
  p_customer_phone text,
  p_customer_address text,
  p_items jsonb
) returns jsonb
language plpgsql security definer set search_path = public
as $fn$
declare
  v_customer uuid;
  v_order uuid;
  v_total numeric(12,2) := 0;
  v_inv_no text;
  v_token uuid;
  itm jsonb;
begin
  insert into customers (seller_id, name, phone, address)
  values (p_seller, p_customer_name, p_customer_phone, nullif(p_customer_address,''))
  on conflict (seller_id, phone) do update
    set name = excluded.name,
        address = coalesce(excluded.address, customers.address)
  returning id into v_customer;

  insert into orders (seller_id, customer_id) values (p_seller, v_customer)
  returning id into v_order;

  for itm in select value from jsonb_array_elements(p_items) loop
    insert into order_items (order_id, item_name, quantity, unit_price_inr)
    values (v_order, itm->>'name', (itm->>'qty')::int, (itm->>'price')::numeric);
    v_total := v_total + ((itm->>'qty')::int * (itm->>'price')::numeric);
  end loop;

  update orders set total_inr = v_total, status = 'confirmed' where id = v_order;

  v_inv_no := next_invoice_number(p_seller);
  insert into invoices (seller_id, order_id, invoice_number)
  values (p_seller, v_order, v_inv_no)
  returning public_token into v_token;

  return jsonb_build_object(
    'invoice_number', v_inv_no,
    'total', v_total,
    'public_token', v_token
  );
end;
$fn$;

-- Mark paid on behalf of a seller (bot server only)
create or replace function mark_paid_by_seller(p_seller uuid, p_invoice_number text)
returns boolean
language plpgsql security definer set search_path = public
as $fn$
begin
  update invoices set is_paid = true, paid_at = now()
    where seller_id = p_seller and upper(invoice_number) = upper(p_invoice_number) and not is_paid;
  update orders set payment_status = 'paid'
    where id = (select order_id from invoices
                where seller_id = p_seller and upper(invoice_number) = upper(p_invoice_number));
  return found;
end;
$fn$;

-- Public invoice fetch by token (for the shareable /inv/<token> page)
create or replace function get_public_invoice(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $fn$
declare
  result jsonb;
begin
  select jsonb_build_object(
    'invoice_number', i.invoice_number,
    'is_paid', i.is_paid,
    'generated_at', i.generated_at,
    'business_name', s.business_name,
    'seller_phone', s.phone,
    'upi_id', s.upi_id,
    'customer_name', c.name,
    'customer_phone', c.phone,
    'customer_address', c.address,
    'total', o.total_inr,
    'items', (
      select jsonb_agg(jsonb_build_object(
        'name', oi.item_name, 'qty', oi.quantity, 'price', oi.unit_price_inr))
      from order_items oi where oi.order_id = o.id
    )
  ) into result
  from invoices i
  join orders o on o.id = i.order_id
  join sellers s on s.id = i.seller_id
  join customers c on c.id = o.customer_id
  where i.public_token = p_token;

  return result;
end;
$fn$;

grant execute on function get_public_invoice(uuid) to anon, authenticated;

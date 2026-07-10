-- v0.3.0 migration: auth linkage, RLS policies, invoice RPCs
-- Applied to Supabase project qhrucvdwguxvnbuwrvae on 2026-07-10

alter table sellers add column if not exists auth_user_id uuid unique references auth.users(id);

create or replace function current_seller_id()
returns uuid language sql stable security definer set search_path = public as $fn$
  select id from sellers where auth_user_id = auth.uid()
$fn$;

drop policy if exists "sellers select own" on sellers;
drop policy if exists "sellers insert own" on sellers;
drop policy if exists "sellers update own" on sellers;
drop policy if exists "own customers" on customers;
drop policy if exists "own orders" on orders;
drop policy if exists "own order_items" on order_items;
drop policy if exists "own invoices" on invoices;

create policy "sellers select own" on sellers for select using (auth_user_id = auth.uid());
create policy "sellers insert own" on sellers for insert with check (auth_user_id = auth.uid());
create policy "sellers update own" on sellers for update using (auth_user_id = auth.uid());
create policy "own customers" on customers for all
  using (seller_id = current_seller_id()) with check (seller_id = current_seller_id());
create policy "own orders" on orders for all
  using (seller_id = current_seller_id()) with check (seller_id = current_seller_id());
create policy "own order_items" on order_items for all
  using (order_id in (select id from orders where seller_id = current_seller_id()))
  with check (order_id in (select id from orders where seller_id = current_seller_id()));
create policy "own invoices" on invoices for all
  using (seller_id = current_seller_id()) with check (seller_id = current_seller_id());

create or replace function create_invoice(
  p_customer_name text,
  p_customer_phone text,
  p_customer_address text,
  p_customer_email text,
  p_items jsonb
) returns jsonb
language plpgsql security definer set search_path = public
as $fn$
declare
  v_seller uuid;
  v_customer uuid;
  v_order uuid;
  v_total numeric(12,2) := 0;
  v_inv_no text;
  itm jsonb;
begin
  select id into v_seller from sellers where auth_user_id = auth.uid();
  if v_seller is null then
    raise exception 'No seller profile for this user';
  end if;

  insert into customers (seller_id, name, phone, address, email)
  values (v_seller, p_customer_name, p_customer_phone, nullif(p_customer_address,''), nullif(p_customer_email,''))
  on conflict (seller_id, phone) do update
    set name = excluded.name,
        address = coalesce(excluded.address, customers.address),
        email = coalesce(excluded.email, customers.email)
  returning id into v_customer;

  insert into orders (seller_id, customer_id) values (v_seller, v_customer)
  returning id into v_order;

  for itm in select value from jsonb_array_elements(p_items) loop
    insert into order_items (order_id, item_name, quantity, unit_price_inr)
    values (v_order, itm->>'name', (itm->>'qty')::int, (itm->>'price')::numeric);
    v_total := v_total + ((itm->>'qty')::int * (itm->>'price')::numeric);
  end loop;

  update orders set total_inr = v_total, status = 'confirmed' where id = v_order;

  v_inv_no := next_invoice_number(v_seller);
  insert into invoices (seller_id, order_id, invoice_number)
  values (v_seller, v_order, v_inv_no);

  return jsonb_build_object('invoice_number', v_inv_no, 'total', v_total);
end;
$fn$;

create or replace function mark_invoice_paid(p_invoice_number text)
returns boolean
language plpgsql security definer set search_path = public
as $fn$
declare
  v_seller uuid;
begin
  select id into v_seller from sellers where auth_user_id = auth.uid();
  update invoices set is_paid = true, paid_at = now()
    where seller_id = v_seller and invoice_number = p_invoice_number and not is_paid;
  update orders set payment_status = 'paid'
    where id = (select order_id from invoices
                where seller_id = v_seller and invoice_number = p_invoice_number);
  return found;
end;
$fn$;

grant execute on function create_invoice(text,text,text,text,jsonb) to authenticated;
grant execute on function mark_invoice_paid(text) to authenticated;
grant execute on function current_seller_id() to authenticated;

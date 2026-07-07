-- ============================================================
-- GetWeChaat — Supabase (Postgres) schema
-- Run this in Supabase: SQL Editor -> New query -> paste -> Run
-- ============================================================

-- Sellers: each home-based business on the platform
create table sellers (
  id            uuid primary key default gen_random_uuid(),
  business_name text not null,
  owner_name    text not null,
  phone         text not null unique,          -- WhatsApp number, E.164 e.g. +91XXXXXXXXXX
  email         text,
  upi_id        text,                          -- for payment collection
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

-- Products: catalog items, unique serial number per seller
create table products (
  id            uuid primary key default gen_random_uuid(),
  seller_id     uuid not null references sellers(id) on delete cascade,
  serial_number text not null,                 -- e.g. GW-0001, unique within a seller
  name          text not null,
  description   text,
  category      text,                          -- e.g. 'stud', 'chain', 'bangle'
  price_inr     numeric(12,2) not null check (price_inr >= 0),
  quantity      integer not null default 0 check (quantity >= 0),
  image_url     text,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (seller_id, serial_number)
);

-- Customers: captured per seller, with WhatsApp promo opt-in
create table customers (
  id               uuid primary key default gen_random_uuid(),
  seller_id        uuid not null references sellers(id) on delete cascade,
  name             text not null,
  phone            text not null,              -- WhatsApp number
  address          text,
  whatsapp_opt_in  boolean not null default false,  -- required for promo messages
  created_at       timestamptz not null default now(),
  unique (seller_id, phone)
);

-- Orders
create type order_status   as enum ('pending','confirmed','dispatched','delivered','cancelled');
create type payment_status as enum ('pending','paid','failed','refunded');

create table orders (
  id             uuid primary key default gen_random_uuid(),
  seller_id      uuid not null references sellers(id) on delete cascade,
  customer_id    uuid not null references customers(id),
  status         order_status not null default 'pending',
  payment_status payment_status not null default 'pending',
  payment_ref    text,                         -- Razorpay/Cashfree reference
  total_inr      numeric(12,2) not null default 0,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table order_items (
  id             uuid primary key default gen_random_uuid(),
  order_id       uuid not null references orders(id) on delete cascade,
  product_id     uuid not null references products(id),
  quantity       integer not null check (quantity > 0),
  unit_price_inr numeric(12,2) not null       -- price at time of order
);

-- Invoices: INV-YYYY-NNNN, sequence resets each year, atomic counter
create table invoice_counters (
  year     integer primary key,
  last_seq integer not null default 0
);

create table invoices (
  id             uuid primary key default gen_random_uuid(),
  order_id       uuid not null unique references orders(id),
  invoice_number text not null unique,         -- INV-2026-0001
  pdf_url        text,                         -- Supabase Storage URL
  generated_at   timestamptz not null default now()
);

-- Atomic invoice number generator (prevents duplicates under concurrency)
create or replace function next_invoice_number()
returns text
language plpgsql
as $$
declare
  y   integer := extract(year from now())::integer;
  seq integer;
begin
  insert into invoice_counters (year, last_seq)
  values (y, 1)
  on conflict (year)
  do update set last_seq = invoice_counters.last_seq + 1
  returning last_seq into seq;

  return 'INV-' || y || '-' || lpad(seq::text, 4, '0');
end;
$$;

-- Helpful indexes
create index idx_products_seller   on products(seller_id) where is_active;
create index idx_customers_seller  on customers(seller_id);
create index idx_orders_seller     on orders(seller_id, created_at desc);
create index idx_order_items_order on order_items(order_id);

-- Auto-update updated_at
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger products_touch before update on products
  for each row execute function touch_updated_at();
create trigger orders_touch before update on orders
  for each row execute function touch_updated_at();

-- Row Level Security: enabled now, policies added when Supabase Auth is wired up.
-- The API uses the service-role key which bypasses RLS; these protect direct access.
alter table sellers          enable row level security;
alter table products         enable row level security;
alter table customers        enable row level security;
alter table orders           enable row level security;
alter table order_items      enable row level security;
alter table invoices         enable row level security;
alter table invoice_counters enable row level security;

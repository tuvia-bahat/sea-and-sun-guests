-- הדביקו את כל הקובץ ב-Supabase: SQL Editor -> New query -> Run

create table if not exists public.visitors (
  id          bigint generated always as identity primary key,
  token       uuid not null unique,
  plate       text not null check (plate ~ '^[0-9]{5,8}$'),
  phone       text not null check (phone ~ '^0[0-9]{8,9}$'),
  host        text not null check (char_length(host) between 2 and 80),
  status      text not null default 'pending' check (status in ('pending','entered','rejected')),
  created_at  timestamptz not null default now(),
  handled_at  timestamptz
);
create index if not exists visitors_status_idx on public.visitors (status, created_at);

alter table public.visitors enable row level security;

-- אורח (anon): יכול רק להוסיף רישום חדש. לא יכול לקרוא ולא לשנות כלום.
drop policy if exists guest_insert on public.visitors;
create policy guest_insert on public.visitors
  for insert to anon
  with check (status = 'pending' and handled_at is null);

-- קבלה (משתמש מחובר): קריאה ועדכון.
drop policy if exists staff_select on public.visitors;
create policy staff_select on public.visitors for select to authenticated using (true);
drop policy if exists staff_update on public.visitors;
create policy staff_update on public.visitors for update to authenticated using (true) with check (true);

-- האורח יכול לבדוק רק את הסטטוס של הרישום שלו, לפי הטוקן האקראי שלו.
create or replace function public.get_status(t uuid)
returns text language sql security definer set search_path = public as
$$ select status from public.visitors where token = t $$;
revoke all on function public.get_status(uuid) from public;
grant execute on function public.get_status(uuid) to anon, authenticated;

-- הגבלת ספאם: עד 5 רישומים לאותו טלפון ב-10 דקות.
create or replace function public.limit_spam()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.visitors
      where phone = new.phone and created_at > now() - interval '10 minutes') >= 5 then
    raise exception 'too_many';
  end if;
  return new;
end $$;
drop trigger if exists visitors_limit on public.visitors;
create trigger visitors_limit before insert on public.visitors
  for each row execute function public.limit_spam();

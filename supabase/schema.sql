-- מערכת רישום אורחים - סי אנד סאן
-- מיועד לרוץ בתוך פרויקט Supabase קיים בלי לגעת בשום דבר שכבר קיים:
-- כל האובייקטים כאן מתחילים ב-seasun_ והסקריפט לא מוחק ולא משנה שום טבלה אחרת.
-- הדביקו ב-SQL Editor -> New query -> Run

create table if not exists public.seasun_visitors (
  id          bigint generated always as identity primary key,
  token       uuid not null unique,
  plate       text not null check (plate ~ '^[0-9]{5,8}$'),
  phone       text not null check (phone ~ '^0[0-9]{8,9}$'),
  host        text not null check (char_length(host) between 2 and 80),
  status      text not null default 'pending' check (status in ('pending','entered','rejected')),
  created_at  timestamptz not null default now(),
  handled_at  timestamptz
);
create index if not exists seasun_visitors_status_idx on public.seasun_visitors (status, created_at);

-- רשימת עובדי הקבלה המורשים (רק מי שברשימה רואה ומטפל באורחים)
create table if not exists public.seasun_staff (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.seasun_staff enable row level security;   -- בלי policies: אף אחד לא ניגש ישירות

create or replace function public.seasun_is_staff()
returns boolean language sql stable security definer set search_path = public as
$$ select exists (select 1 from public.seasun_staff where user_id = auth.uid()) $$;
revoke all on function public.seasun_is_staff() from public;
grant execute on function public.seasun_is_staff() to authenticated;

alter table public.seasun_visitors enable row level security;

-- אורח (anon): רק להוסיף רישום חדש. לא קורא ולא משנה.
drop policy if exists seasun_guest_insert on public.seasun_visitors;
create policy seasun_guest_insert on public.seasun_visitors
  for insert to anon
  with check (status = 'pending' and handled_at is null);

-- קבלה: רק עובדים ברשימה
drop policy if exists seasun_staff_select on public.seasun_visitors;
create policy seasun_staff_select on public.seasun_visitors
  for select to authenticated using (public.seasun_is_staff());
drop policy if exists seasun_staff_update on public.seasun_visitors;
create policy seasun_staff_update on public.seasun_visitors
  for update to authenticated using (public.seasun_is_staff()) with check (public.seasun_is_staff());

-- האורח בודק רק את הסטטוס של הרישום שלו, לפי טוקן אקראי
create or replace function public.seasun_get_status(t uuid)
returns text language sql security definer set search_path = public as
$$ select status from public.seasun_visitors where token = t $$;
revoke all on function public.seasun_get_status(uuid) from public;
grant execute on function public.seasun_get_status(uuid) to anon, authenticated;

-- הגבלת ספאם: עד 5 רישומים לאותו טלפון ב-10 דקות
create or replace function public.seasun_limit_spam()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.seasun_visitors
      where phone = new.phone and created_at > now() - interval '10 minutes') >= 5 then
    raise exception 'too_many';
  end if;
  return new;
end $$;
drop trigger if exists seasun_visitors_limit on public.seasun_visitors;
create trigger seasun_visitors_limit before insert on public.seasun_visitors
  for each row execute function public.seasun_limit_spam();

-- ============ שלב נפרד, אחרי שיצרתם משתמש לקבלה ב-Authentication -> Users ============
-- החליפו את האימייל והריצו:
-- insert into public.seasun_staff (user_id)
--   select id from auth.users where email = 'reception@example.com'
--   on conflict do nothing;

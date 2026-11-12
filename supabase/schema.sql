-- מערכת רישום אורחים - סי אנד סאן
-- מיועד לרוץ בתוך פרויקט Supabase קיים בלי לגעת בשום דבר שכבר קיים:
-- כל האובייקטים כאן מתחילים ב-seasun_ והסקריפט לא מוחק ולא משנה שום טבלה אחרת.
-- לא משתמש בהתחברות (Auth) של Supabase בכלל - הקבלה נכנסת עם סיסמה אחת.
-- הדביקו ב-SQL Editor -> New query -> Run

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.seasun_visitors (
  id          bigint generated always as identity primary key,
  token       uuid not null unique,
  plate       text not null check (plate ~ '^[0-9]{7,8}$'),
  phone       text not null check (phone ~ '^(05[0-9]{8}|07[0-9]{8}|0[23489][0-9]{7})$'),
  host        text not null check (char_length(host) between 2 and 80),
  status      text not null default 'pending' check (status in ('pending','entered','rejected')),
  created_at  timestamptz not null default now(),
  handled_at  timestamptz
);
create index if not exists seasun_visitors_status_idx on public.seasun_visitors (status, created_at);

-- סיסמת הקבלה נשמרת מוצפנת (bcrypt)
create table if not exists public.seasun_settings (
  key   text primary key,
  value text not null
);

alter table public.seasun_visitors enable row level security;
alter table public.seasun_settings enable row level security;  -- בלי policies: אין גישה ישירה

-- אורח (anon): רק להוסיף רישום חדש. אי אפשר לקרוא או לשנות ישירות.
drop policy if exists seasun_guest_insert on public.seasun_visitors;
create policy seasun_guest_insert on public.seasun_visitors
  for insert to anon
  with check (status = 'pending' and handled_at is null);

-- בדיקת סיסמה. בכישלון ממתינים שנייה כדי להאט ניחושים.
create or replace function public.seasun_check(pw text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare ok boolean;
begin
  select exists (select 1 from public.seasun_settings
                 where key = 'reception' and value = crypt(coalesce(pw, ''), value)) into ok;
  if not ok then perform pg_sleep(1); end if;
  return ok;
end $$;

-- רשימת אורחים לקבלה: הממתינים + כל מה שנרשם היום
create or replace function public.seasun_list(pw text)
returns setof public.seasun_visitors language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.seasun_check(pw) then raise exception 'unauthorized'; end if;
  return query select * from public.seasun_visitors
    where status = 'pending'
       or created_at >= (date_trunc('day', now() at time zone 'Asia/Jerusalem') at time zone 'Asia/Jerusalem')
    order by created_at;
end $$;

-- טיפול באורח: entered / rejected / pending (ביטול)
create or replace function public.seasun_handle(pw text, vid bigint, new_status text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.seasun_check(pw) then raise exception 'unauthorized'; end if;
  if new_status not in ('pending','entered','rejected') then raise exception 'bad status'; end if;
  update public.seasun_visitors
     set status = new_status,
         handled_at = case when new_status = 'pending' then null else now() end
   where id = vid;
end $$;

-- האורח בודק רק את הסטטוס של הרישום שלו, לפי טוקן אקראי
create or replace function public.seasun_get_status(t uuid)
returns text language sql security definer set search_path = public as
$$ select status from public.seasun_visitors where token = t $$;

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

-- הרשאות הרצה: רק מה שהאתר צריך
revoke all on function public.seasun_check(text) from public;
revoke all on function public.seasun_list(text) from public;
revoke all on function public.seasun_handle(text, bigint, text) from public;
revoke all on function public.seasun_get_status(uuid) from public;
grant execute on function public.seasun_list(text), public.seasun_handle(text, bigint, text),
                          public.seasun_get_status(uuid) to anon, authenticated;

-- ============ הגדרת סיסמת הקבלה - הריצו בנפרד, אחרי שבחרתם סיסמה ארוכה ============
-- insert into public.seasun_settings (key, value)
--   values ('reception', extensions.crypt('הסיסמה-שלכם-כאן', extensions.gen_salt('bf')))
--   on conflict (key) do update set value = excluded.value;

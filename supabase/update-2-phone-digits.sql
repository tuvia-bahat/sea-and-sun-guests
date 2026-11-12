-- עדכון: טלפון חייב להיות נייד (10 ספרות, 05x), קווי (9 ספרות) או 07x (10 ספרות).
-- הריצו ב-SQL Editor. לא נוגע בשום דבר מחוץ ל-seasun_visitors.
alter table public.seasun_visitors drop constraint if exists seasun_visitors_phone_check;
alter table public.seasun_visitors
  add constraint seasun_visitors_phone_check
  check (phone ~ '^(05[0-9]{8}|07[0-9]{8}|0[23489][0-9]{7})$') not valid;

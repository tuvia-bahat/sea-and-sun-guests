-- עדכון מאוחד: מספר רכב 7 או 8 ספרות, וטלפון תקין (נייד 10 ספרות, קווי 9 ספרות).
-- הדביקו הכול ב-SQL Editor והריצו פעם אחת. נוגע רק בטבלה seasun_visitors.

alter table public.seasun_visitors drop constraint if exists seasun_visitors_plate_check;
alter table public.seasun_visitors
  add constraint seasun_visitors_plate_check check (plate ~ '^[0-9]{7,8}$') not valid;

alter table public.seasun_visitors drop constraint if exists seasun_visitors_phone_check;
alter table public.seasun_visitors
  add constraint seasun_visitors_phone_check
  check (phone ~ '^(05[0-9]{8}|07[0-9]{8}|0[23489][0-9]{7})$') not valid;

-- עדכון: מספר רכב חייב להיות 7 או 8 ספרות בדיוק (גם במסד הנתונים).
-- הריצו ב-SQL Editor. לא נוגע בשום דבר מחוץ ל-seasun_visitors.
alter table public.seasun_visitors drop constraint if exists seasun_visitors_plate_check;
alter table public.seasun_visitors
  add constraint seasun_visitors_plate_check check (plate ~ '^[0-9]{7,8}$') not valid;
-- not valid = רישומי בדיקה ישנים בני 5-6 ספרות (אם יש) לא ימנעו את העדכון, ורישומים חדשים כן נבדקים.

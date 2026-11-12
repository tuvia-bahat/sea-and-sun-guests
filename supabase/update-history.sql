-- היסטוריית אורחים וחיפוש בכל הרשומות. הריצו הכול פעם אחת ב-SQL Editor.
-- מוסיף שתי פונקציות בלבד, ולא נוגע בשום דבר אחר.

-- כל הרשומות, מהחדשה לישנה, עם חיפוש אופציונלי (מספר רכב, טלפון או שם דייר)
create or replace function public.seasun_history(pw text, q text, lim int, off int)
returns setof public.seasun_visitors language plpgsql security definer set search_path = public, extensions as $$
declare
  t text := btrim(coalesce(q, ''));
  d text := regexp_replace(coalesce(q, ''), '[^0-9]', '', 'g');
begin
  if not public.seasun_check(pw) then raise exception 'unauthorized'; end if;
  return query
    select * from public.seasun_visitors v
     where t = ''
        or (d <> '' and (v.plate like '%' || d || '%' or v.phone like '%' || d || '%'))
        or v.host ilike '%' || t || '%'
     order by v.created_at desc
     limit least(greatest(lim, 1), 500) offset greatest(off, 0);
end $$;

-- כל הרישומים של רכב אחד
create or replace function public.seasun_plate_history(pw text, p text)
returns setof public.seasun_visitors language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.seasun_check(pw) then raise exception 'unauthorized'; end if;
  return query
    select * from public.seasun_visitors v
     where v.plate = regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g')
     order by v.created_at desc
     limit 500;
end $$;

revoke all on function public.seasun_history(text, text, int, int) from public;
revoke all on function public.seasun_plate_history(text, text) from public;
grant execute on function public.seasun_history(text, text, int, int) to anon, authenticated;
grant execute on function public.seasun_plate_history(text, text) to anon, authenticated;

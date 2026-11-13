-- תג "אושר בעבר" / "אורח חדש". הריצו פעם אחת ב-SQL Editor.
-- מוסיף פונקציה אחת בלבד, ולא נוגע בשום דבר אחר.

create or replace function public.seasun_known(pw text, plates text[])
returns table(plate text, entered_count bigint, last_entered timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.seasun_check(pw) then raise exception 'unauthorized'; end if;
  return query
    select v.plate, count(*)::bigint, max(v.handled_at)
      from public.seasun_visitors v
     where v.plate = any(plates) and v.status = 'entered'
     group by v.plate;
end $$;

revoke all on function public.seasun_known(text, text[]) from public;
grant execute on function public.seasun_known(text, text[]) to anon, authenticated;

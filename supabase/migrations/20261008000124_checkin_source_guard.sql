-- Members insert their own check-ins only as 'manual' / 'auto' (GPS-checked by
-- on_checkin_insert). 'qr' and 'organizer' check-ins come only from the
-- security-definer RPCs (checkin_by_qr, checkin_by_door, host tools), which
-- bypass RLS. Before this, an app user could insert source 'qr' directly and
-- skip the location check (and so enter lucky draws from home).
drop policy if exists "checkins: insert own" on public.checkins;
create policy "checkins: insert own" on public.checkins for insert to authenticated
  with check (user_id = auth.uid() and source in ('manual', 'auto'));

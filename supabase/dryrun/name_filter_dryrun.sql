-- Dry run for 20261009000128_name_filter.sql. Run AFTER the migration, both
-- inside one transaction that is rolled back:
--   python q.py --tx supabase/migrations/20261009000128_name_filter.sql supabase/dryrun/name_filter_dryrun.sql
-- The last SELECT lists only the checks that FAILED (empty = all good), plus
-- a summary row.

create temp table _cases (input text, kind text, expect text) on commit drop;

-- Must pass: Malaysian names, places, cars and car words (+ Scunthorpe traps).
insert into _cases (input, kind, expect)
select v, k, 'ok' from unnest(array[
  'Ahmad', 'Siti', 'Siti Nurhaliza', 'Wei Ling', 'Tan Wei Ling', 'Kumar', 'Dickson', 'Dickson Tan',
  'Kok Wai', 'Lim Kok Wai', 'Hassan', 'Hassan Ali', 'Assam', 'Assam Laksa', 'Lancer', 'Cockpit',
  'Cocktail', 'Shitake', 'Shiitake', 'Sussex', 'Middlesex', 'Essex', 'Scunthorpe', 'Hancock',
  'Peacock', 'Analisa', 'Anna Lisa', 'Cumming', 'Matsushita', 'Puchong', 'Bangsar', 'Saab', 'Kia',
  'Proton', 'Perodua', 'Myvi', 'Axia', 'Bezza', 'Saga', 'Wira', 'Satria', 'Iswara', 'Kancil',
  'Honda Civic', 'Civic Type R', 'Evo 9', 'Impreza WRX', 'Skyline R34', 'Supra', 'Hilux', 'Ranger',
  'Muhammad Faiz', 'Nur Aisyah', 'Aiman Hakim', 'Mohd Shahrul', 'Nazira', 'Nazim', 'Nazifa',
  'Sohail', 'Soh Ai Ling', 'Wong Bik Ling', 'Chan Kah Hou', 'Lee Chong Wei', 'Ng Kok Seng',
  'Teh Siew Ling', 'Cheng Kim Chuan', 'Ooi Boon Kiat', 'Goh Chee Keong', 'Pang Ah Kow',
  'Muthu', 'Ravi Shankar', 'Arumugam', 'Kavitha', 'Thanabalan', 'Saravanan', 'Pandian',
  'Shah Alam', 'Subang Jaya', 'Petaling Jaya', 'Kepong', 'Cheras', 'Klang', 'Seremban', 'Ipoh',
  'Kuantan', 'Kota Bharu', 'Johor Bahru', 'Kuching', 'Kota Kinabalu', 'Melaka', 'Sungai Buloh',
  'Bukit Jalil', 'Setapak', 'Titiwangsa', 'Pantai Dalam', 'Sekinchan', 'Butterworth', 'Batu Pahat',
  'Pasir Gudang', 'Kampung Baru', 'Kelingking', 'Pukis', 'Kuih Pukis', 'Bak Kut Teh', 'Mamak',
  'Nasi Lemak', 'Teh Tarik', 'Roti Canai', 'Kopitiam', 'Turbo', 'Drift', 'Stance', 'Camber',
  'Coilover', 'Bodykit', 'Exhaust', 'Dyno', 'LSD', 'Limited slip', 'Track day', 'Sepang',
  'Night Meet', 'Sunday Drive', 'JDM Malaysia', 'Euro Club', 'Modified', 'Mods Garage',
  'Polished Rides', 'Officina', 'Supper', 'Staffy', 'Pakistan', 'Cocky', 'Classic', 'Massey',
  'Glass', 'Grass Track', 'Bass Boost', 'Passion', 'Compass', 'Isisaki', 'Methodist', 'Heroine',
  'Ganjar', 'Diunsa', 'Babington', 'Siala', 'Pantai', 'Kota', 'Kotak', 'Lanca',
  'CB400', 'Honda CB400', '曹', '王伟', '陈家豪', '李明', '张伟', '体育', '黄志明',
  '赛车', '汽车俱乐部', '12v_sdn_bhd', 'teh16010', 'civic88', 'ek9', 'evo4', 'r34', 's2000',
  'gt86', '370z', '4age', 'b16', 'sr20', 'rb26', 's15', 'ae86', 'mx5', 'e46', 'e30', 'c63',
  'rs3', 'a45', 'fd3s', '1jz', '2jz', 'bigboss', 'mingshun', 'sean', 'keanechai', 'caiping',
  'lalazai', 'keith', 'hailey', 'testing',
  -- More towns (Semporna once tripped "porn").
  'Semporna', 'Sandakan', 'Tawau', 'Lahad Datu', 'Keningau', 'Ranau', 'Kudat', 'Miri', 'Sibu',
  'Bintulu', 'Kapit', 'Mukah', 'Limbang', 'Sri Aman', 'Serian', 'Alor Setar', 'Sungai Petani',
  'Kulim', 'Kangar', 'Taiping', 'Teluk Intan', 'Lumut', 'Sitiawan', 'Kampar', 'Tapah', 'Bentong',
  'Raub', 'Temerloh', 'Kuala Lipis', 'Mentakab', 'Jerantut', 'Dungun', 'Kemaman', 'Marang', 'Besut',
  'Kuala Terengganu', 'Pasir Mas', 'Tumpat', 'Machang', 'Gua Musang', 'Muar', 'Segamat', 'Kluang',
  'Pontian', 'Kota Tinggi', 'Mersing', 'Kulai', 'Skudai', 'Senai', 'Nilai', 'Port Dickson', 'Rembau',
  'Tampin', 'Kuala Pilah', 'Jasin', 'Alor Gajah', 'Ayer Keroh', 'Rawang', 'Kajang', 'Semenyih',
  'Bangi', 'Putrajaya', 'Cyberjaya', 'Dengkil', 'Banting', 'Kuala Selangor', 'Sabak Bernam',
  'Ampang', 'Gombak', 'Selayang', 'Batu Caves', 'Sentul', 'Damansara', 'Sri Hartamas', 'Mont Kiara',
  'Bukit Bintang', 'Chow Kit', 'Pudu', 'Brickfields', 'Segambut', 'Wangsa Maju', 'Setiawangsa',
  'Sri Petaling', 'Kuchai Lama', 'Taman Desa', 'Kinrara', 'Bandar Sunway', 'USJ', 'Glenmarie',
  'Kota Damansara', 'Tropicana', 'Genting Highlands', 'Cameron Highlands', 'Langkawi', 'Pangkor',
  'Tioman', 'Redang', 'Perhentian', 'Penang', 'Georgetown', 'Bayan Lepas', 'Balik Pulau',
  'Jelutong', 'Air Itam', 'Gurney', 'Batu Ferringhi', 'Seberang Jaya', 'Bukit Mertajam',
  'Nibong Tebal', 'Kepala Batas', 'Simpang Ampat', 'Pantai Remis', 'Kuala Kangsar', 'Gerik',
  'Parit Buntar', 'Bagan Serai', 'Bagan Datuk', 'Chukai', 'Pekan', 'Rompin', 'Endau', 'Labuan',
  'Papar', 'Beaufort', 'Tenom', 'Kota Belud', 'Tuaran', 'Penampang', 'Putatan', 'Inanam',
  -- Car makes, tuners and parts.
  'Lamborghini', 'Ferrari', 'Porsche', 'Mercedes', 'BMW', 'Audi', 'Volkswagen', 'Volvo', 'Mazda',
  'Nissan', 'Toyota', 'Subaru', 'Mitsubishi', 'Suzuki', 'Daihatsu', 'Lexus', 'Infiniti', 'Hyundai',
  'Peugeot', 'Renault', 'Citroen', 'Chery', 'Geely', 'BYD', 'Haval', 'Tesla', 'Mini Cooper',
  'Jaguar', 'Land Rover', 'Bentley', 'Rolls Royce', 'McLaren', 'Lotus', 'Alfa Romeo', 'Abarth',
  'Ford Mustang', 'Chevrolet', 'Isuzu D-Max', 'Kawasaki Ninja', 'Yamaha', 'Ducati', 'Harley Davidson',
  'Vespa', 'Hotchkis', 'Cusco', 'Tein', 'Bilstein', 'Recaro', 'Bride', 'Sparco', 'Momo', 'Nardi',
  'Rays', 'Volk', 'Enkei', 'BBS', 'HKS', 'Greddy', 'Tomei', 'Spoon', 'Mugen', 'Nismo', 'TRD', 'STi',
  'Ralliart', 'AMG', 'M Power', 'Akrapovic', 'Titanium', 'Analog', 'Assassin', 'Cumulus', 'Shabu Shabu',
  'Shifter', 'Shift Lock', 'Pit Stop', 'Hatchback', 'Cockatoo', 'Dickies', 'Passenger', 'Bassist'
]) as t(v), unnest(array['name', 'handle']) as k(k);

-- Event and group titles (title kind: no reserved check).
insert into _cases (input, kind, expect) values
  ('Police Day Car Show', 'title', 'ok'), ('Official launch: TT Spot x MIAPEX', 'title', 'ok'),
  ('Sultan Ismail road meet', 'title', 'ok'), ('Friday night mamak', 'title', 'ok'),
  ('Assam laksa run', 'title', 'ok'), ('Cocktail & cars', 'title', 'ok'),
  ('Sussex Lotus owners', 'title', 'ok');

-- Must fail: rude, sexual, hate, drugs, slurs.
insert into _cases (input, kind, expect)
select v, 'name', 'bad' from unnest(array[
  'fuck', 'Fuck You', 'fuckboy', 'motherfucker', 'shit', 'Big Shit', 's.h.i.t', 'bullshit', 'bitch',
  'son of a bitch', 'asshole', 'ass', 'dick', 'Big Dick', 'cock', 'cunt', 'pussy', 'slut', 'whore',
  'porn', 'pornstar', 'sex', 'sex god', 'nudes', 'horny', 'dildo', 'blowjob', 'babi', 'Babi Hutan',
  'puki', 'pukimak', 'pukimakkau', 'sial', 'bangsat', 'butoh', 'pantat', 'lancau', 'kote',
  'haram jadah', 'cibai', 'cb', 'CB Tan', 'chibai', 'kanina', 'kan ni na', 'knn', 'lanjiao', 'diu',
  'pok gai', 'hamsap', 'sohai', 'pundek', '操', '操你妈', '屌你老母', '鸡巴', '婊子', '他妈的', '干你娘',
  '傻逼', '仆街', 'keling', 'tongsan', 'nigger', 'nigga', 'chink', 'nazi', 'Hitler Fan', 'isis',
  'ganja', 'syabu', 'meth', 'cocaine', 'fuuuuck', 'shiiit', 'cibaiiii'
]) as t(v);

-- Must fail: leetspeak.
insert into _cases (input, kind, expect)
select v, 'handle', 'bad' from unnest(array[
  'f_u_c_k', 'fu.ck', 'sh1t', '$hit', 'b1tch', 'a55', 'a$$hole', 'd1ck', 'c0ck', 'p0rn',
  's3x', 'pu55y', 'b4b1', 'c1b4i', 'kn_n', 'l4nj140', 'n4z1', 'g4nj4', 'b!tch', 'c!bai', '5ial'
]) as t(v);

-- Reserved handles and names.
insert into _cases (input, kind, expect)
select v, 'handle', 'reserved' from unnest(array[
  'ttspot', 'tt_spot', 'ttspot_official', 'ttspotofficial', 'ttsp0t', 'titi', 't1t1', 'titi_onboard1',
  'admin', 'admin123', 'admin_kl', '4dmin', 'administrator', 'moderator', 'mod', 'mod_team',
  'support', 'support_team', 'official', 'official_civic', 'staff', 'staff1', 'polis', 'polis_kl',
  'police', 'pdrm', 'jpj', 'jpj_my', 'sultan', 'agong', 'kerajaan'
]) as t(v);
insert into _cases (input, kind, expect) values
  ('TT Spot', 'name', 'reserved'), ('TT Spot Official', 'name', 'reserved'),
  ('TiTi', 'name', 'reserved'), ('Admin', 'name', 'reserved'), ('Admin Kumar', 'name', 'reserved'),
  ('PDRM', 'name', 'reserved'), ('Polis Diraja', 'name', 'reserved'), ('Official Civic Club', 'name', 'reserved');

create temp table _out (check_name text, input text, kind text, expect text, got text, ok boolean) on commit drop;

insert into _out
select 'name_problem', c.input, c.kind, c.expect, public.name_problem(c.input, c.kind),
       case c.expect
         when 'ok' then public.name_problem(c.input, c.kind) is null
         when 'bad' then public.name_problem(c.input, c.kind) = 'That name isn''t allowed. Try another.'
         else public.name_problem(c.input, c.kind) = 'That name is reserved.'
       end
from _cases c;

-- Triggers --------------------------------------------------------------------

do $t$
declare
  v_member uuid;
  v_admin uuid;
  v_club uuid;
  v_conv uuid;
  v_name text;
  v_err text;
  v_reason text;
begin
  select id into v_member from public.profiles where not is_admin and username is not null order by created_at limit 1;
  select id into v_admin from public.profiles where is_admin order by created_at limit 1;

  -- check_name as anon (no JWT) and as a member.
  perform set_config('request.jwt.claims', '', true);
  insert into _out values ('check_name anon', 'fuck', 'handle', 'bad', public.check_name('fuck', 'handle'),
    public.check_name('fuck', 'handle') = 'That name isn''t allowed. Try another.');
  perform set_config('request.jwt.claims', json_build_object('sub', v_member, 'role', 'authenticated')::text, true);
  insert into _out values ('check_name member', 'admin', 'handle', 'reserved', public.check_name('admin', 'handle'),
    public.check_name('admin', 'handle') = 'That name is reserved.');

  -- Member: bad username rejected.
  v_err := null;
  begin
    update public.profiles set username = 'cibai_king' where id = v_member;
  exception when others then v_err := sqlerrm;
  end;
  insert into _out values ('trigger member bad username', 'cibai_king', 'handle', 'bad', v_err, v_err = 'That name isn''t allowed. Try another.');

  -- Member: leet display name rejected.
  v_err := null;
  begin
    update public.profiles set display_name = 'B1tch Please' where id = v_member;
  exception when others then v_err := sqlerrm;
  end;
  insert into _out values ('trigger member leet display', 'B1tch Please', 'name', 'bad', v_err, v_err = 'That name isn''t allowed. Try another.');

  -- Member: reserved username rejected.
  v_err := null;
  begin
    update public.profiles set username = 'ttspot_official' where id = v_member;
  exception when others then v_err := sqlerrm;
  end;
  insert into _out values ('trigger member reserved', 'ttspot_official', 'handle', 'reserved', v_err, v_err = 'That name is reserved.');

  -- Member: a normal rename passes.
  v_err := null;
  begin
    update public.profiles set display_name = 'Dickson Tan' where id = v_member;
  exception when others then v_err := sqlerrm;
  end;
  insert into _out values ('trigger member normal', 'Dickson Tan', 'name', 'ok', v_err, v_err is null);

  -- Member with an old bad name can still edit other columns (and the name
  -- itself unchanged). Plant the old name as SQL (no auth user) first.
  perform set_config('request.jwt.claims', '', true);
  update public.profiles set display_name = 'Old Cibai Name' where id = v_member;
  perform set_config('request.jwt.claims', json_build_object('sub', v_member, 'role', 'authenticated')::text, true);
  v_err := null;
  begin
    update public.profiles set bio = 'Just a bio change' where id = v_member;
    update public.profiles set display_name = display_name, bio = 'again' where id = v_member;
  exception when others then v_err := sqlerrm;
  end;
  insert into _out values ('trigger other columns', 'Old Cibai Name', 'name', 'ok', v_err, v_err is null);

  -- Admin: reserved handle allowed.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_err := null;
  begin
    update public.profiles set display_name = 'TT Spot' where id = v_admin;
  exception when others then v_err := sqlerrm;
  end;
  insert into _out values ('trigger admin reserved', 'TT Spot', 'name', 'ok', v_err, v_err is null);
  insert into _out values ('check_name admin', 'ttspot', 'handle', 'ok', public.check_name('ttspot', 'handle'), public.check_name('ttspot', 'handle') is null);

  -- SQL / service role (no auth user): reserved handle allowed.
  perform set_config('request.jwt.claims', '', true);
  v_err := null;
  begin
    update public.profiles set username = 'ttspot_test_sql' where id = v_member;
  exception when others then v_err := sqlerrm;
  end;
  insert into _out values ('trigger sql reserved', 'ttspot_test_sql', 'handle', 'ok', v_err, v_err is null);

  -- Clubs: member insert with a bad name, then a normal one.
  perform set_config('request.jwt.claims', json_build_object('sub', v_member, 'role', 'authenticated')::text, true);
  v_err := null;
  begin
    insert into public.clubs (name, owner_id, avatar_url) values ('Kanina Racing', v_member, 'https://example.com/logo.png');
  exception when others then v_err := sqlerrm;
  end;
  insert into _out values ('trigger club bad', 'Kanina Racing', 'name', 'bad', v_err, v_err = 'That name isn''t allowed. Try another.');

  -- Friends' group: a rude title is refused, a normal one passes, and a
  -- rename to a rude title is refused.
  v_err := null;
  begin
    insert into public.conversations (kind, title, created_by) values ('group', 'Lanjiao gang', v_member);
  exception when others then v_err := sqlerrm;
  end;
  insert into _out values ('trigger group title', 'Lanjiao gang', 'title', 'bad', v_err, v_err = 'That name isn''t allowed. Try another.');
  v_err := null;
  begin
    insert into public.conversations (kind, title, created_by) values ('group', 'Assam laksa gang', v_member) returning id into v_conv;
    update public.conversations set photo_url = null where id = v_conv;
    update public.conversations set title = 'Diu lei' where id = v_conv;
  exception when others then v_err := sqlerrm;
  end;
  insert into _out values ('trigger group rename', 'Diu lei', 'title', 'bad', v_err, v_err = 'That name isn''t allowed. Try another.');

  -- Event title update by its (non-admin) host.
  select e.id, e.organizer_id into v_conv, v_club from public.events e
  join public.profiles p on p.id = e.organizer_id and not p.is_admin
  order by e.created_at desc limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_club, 'role', 'authenticated')::text, true);
  v_err := null;
  begin
    update public.events set title = 'Pukimak meet' where id = v_conv;
  exception when others then v_err := sqlerrm;
  end;
  insert into _out values ('trigger event title', 'Pukimak meet', 'title', 'bad', v_err, v_err = 'That name isn''t allowed. Try another.');
  v_err := null;
  begin
    update public.events set description = coalesce(description, '') || ' ' where id = v_conv;
  exception when others then v_err := sqlerrm;
  end;
  insert into _out values ('trigger event other column', '(description)', 'title', 'ok', v_err, v_err is null);

  -- Partner application with a rude business name.
  v_err := null;
  begin
    insert into public.partner_applications (user_id, kind, business_name, business_type)
    values (v_member, 'organizer', 'Bangsat Motors', 'organizer');
  exception when others then v_err := sqlerrm;
  end;
  insert into _out values ('trigger partner name', 'Bangsat Motors', 'title', 'bad', v_err, v_err = 'That name isn''t allowed. Try another.');
end;
$t$;

select * from (
  select check_name, input, kind, expect, got, ok from _out where not coalesce(ok, false)
  union all
  select 'SUMMARY', count(*)::text || ' checks', null, null, count(*) filter (where not coalesce(ok, false))::text || ' failed', null from _out
) r;

-- Panier Protéiné : amis, fil d'activité et bravos.
-- À exécuter une fois dans Supabase → SQL Editor (après setup.sql).

create table if not exists public.social_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  pseudo text not null unique check (char_length(pseudo) between 3 and 20),
  code text not null unique,
  share boolean not null default true,
  stats jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.friendships (
  id bigint generated always as identity primary key,
  requester uuid not null references auth.users (id) on delete cascade,
  addressee uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  unique (requester, addressee)
);

create table if not exists public.activities (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  title text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.kudos (
  activity_id bigint not null references public.activities (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  primary key (activity_id, user_id)
);

-- Liens d'amitié (acceptés ou en attente) entre deux comptes.
create or replace function public.are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from friendships where status = 'accepted'
    and ((requester = a and addressee = b) or (requester = b and addressee = a)));
$$;
create or replace function public.are_related(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from friendships
    where (requester = a and addressee = b) or (requester = b and addressee = a));
$$;

-- Ajout d'un ami par son code (on ne peut pas lister les profils des inconnus).
create or replace function public.add_friend(friend_code text) returns text
language plpgsql security definer set search_path = public as $$
declare target uuid;
begin
  select user_id into target from social_profiles where code = upper(trim(friend_code));
  if target is null then raise exception 'Code introuvable'; end if;
  if target = auth.uid() then raise exception 'C''est ton propre code'; end if;
  if are_related(auth.uid(), target) then return 'already'; end if;
  insert into friendships (requester, addressee) values (auth.uid(), target);
  return 'sent';
end $$;
grant execute on function public.add_friend(text) to authenticated;

alter table public.social_profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.activities enable row level security;
alter table public.kudos enable row level security;

-- Profils : visibles par soi-même et par les comptes liés (amis ou demande en cours).
create policy "voir profils" on public.social_profiles for select
  using (user_id = auth.uid() or are_related(auth.uid(), user_id));
create policy "creer son profil" on public.social_profiles for insert with check (user_id = auth.uid());
create policy "modifier son profil" on public.social_profiles for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Amitiés : chacun voit les siennes, le destinataire accepte, chacun peut supprimer.
create policy "voir ses liens" on public.friendships for select using (auth.uid() in (requester, addressee));
create policy "accepter" on public.friendships for update
  using (addressee = auth.uid()) with check (status = 'accepted');
create policy "supprimer" on public.friendships for delete using (auth.uid() in (requester, addressee));

-- Activités : visibles par soi-même et par les amis acceptés, si le partage est activé.
create policy "voir activites" on public.activities for select using (
  user_id = auth.uid() or (are_friends(auth.uid(), user_id)
    and coalesce((select share from social_profiles p where p.user_id = activities.user_id), true)));
create policy "publier" on public.activities for insert with check (user_id = auth.uid());
create policy "effacer" on public.activities for delete using (user_id = auth.uid());

-- Bravos : sur ses activités ou celles de ses amis.
create policy "voir bravos" on public.kudos for select using (exists (
  select 1 from activities a where a.id = activity_id and (a.user_id = auth.uid() or are_friends(auth.uid(), a.user_id))));
create policy "donner bravo" on public.kudos for insert with check (user_id = auth.uid() and exists (
  select 1 from activities a where a.id = activity_id and are_friends(auth.uid(), a.user_id)));
create policy "retirer bravo" on public.kudos for delete using (user_id = auth.uid());

-- Accès pour les comptes connectés (la sécurité reste assurée par les règles ci-dessus).
grant select, insert, update, delete on public.social_profiles, public.friendships, public.activities, public.kudos to authenticated;

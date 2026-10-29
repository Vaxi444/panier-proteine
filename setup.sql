-- Panier Protéiné : table de sauvegarde, une ligne par compte.
create table if not exists public.user_data (
  user_id uuid primary key references auth.users (id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.user_data enable row level security;

-- Chaque compte ne peut lire et écrire que sa propre ligne.
create policy "lire ses donnees" on public.user_data
  for select using (auth.uid() = user_id);
create policy "creer ses donnees" on public.user_data
  for insert with check (auth.uid() = user_id);
create policy "modifier ses donnees" on public.user_data
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

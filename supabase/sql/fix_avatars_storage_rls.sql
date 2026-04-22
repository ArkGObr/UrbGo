-- Primeiro garante que o bucket 'avatars' existe
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Garante que o bucket está público caso já existisse
update storage.buckets set public = true where id = 'avatars';


-- Política de leitura (qualquer um pode ler imagens públicas do bucket avatars)
drop policy if exists "Avatars are publicly accessible" on storage.objects;
create policy "Avatars are publicly accessible" 
on storage.objects for select 
using (bucket_id = 'avatars');

-- Política de inserção (apenas usuários autenticados)
drop policy if exists "Users can upload their own avatar" on storage.objects;
create policy "Users can upload their own avatar" 
on storage.objects for insert 
with check (
    bucket_id = 'avatars' 
    and auth.role() = 'authenticated'
);

-- Política de atualização (apenas usuários autenticados)
drop policy if exists "Users can update their own avatar" on storage.objects;
create policy "Users can update their own avatar" 
on storage.objects for update 
using (
    bucket_id = 'avatars' 
    and auth.role() = 'authenticated'
);

-- Política de deleção (opcional: apenas usuários autenticados)
drop policy if exists "Users can delete their own avatar" on storage.objects;
create policy "Users can delete their own avatar" 
on storage.objects for delete 
using (
    bucket_id = 'avatars' 
    and auth.role() = 'authenticated'
);

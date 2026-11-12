-- Storage needs to be able to see an object before it can delete or replace it. The bucket is public, so reads by URL
-- never go through policies; this only lets a signed-in user find (and therefore delete) files in their own folder.
create policy photos_select_own on storage.objects for select to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

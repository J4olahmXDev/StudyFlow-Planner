begin;

create table if not exists public.studyflow_workspaces (
    workspace text primary key check (workspace ~ '^[0-9a-f]{64}$'),
    revision bigint not null check (revision > 0),
    ciphertext text not null check (length(ciphertext) between 40 and 3000000)
);

alter table public.studyflow_workspaces enable row level security;
revoke all on public.studyflow_workspaces from public, anon, authenticated;

create or replace function public.studyflow_read(p_workspace text)
returns table (revision bigint, ciphertext text)
language sql stable security definer set search_path = ''
as $$
    select w.revision, w.ciphertext
    from public.studyflow_workspaces w
    where w.workspace = p_workspace and p_workspace ~ '^[0-9a-f]{64}$';
$$;

create or replace function public.studyflow_write(p_workspace text, p_expected bigint, p_ciphertext text)
returns boolean
language plpgsql security definer set search_path = ''
as $$
begin
    if p_workspace is null or p_workspace !~ '^[0-9a-f]{64}$' or
       p_expected is null or p_expected < 0 or p_expected >= 9007199254740991 or
       p_ciphertext is null or length(p_ciphertext) not between 40 and 3000000 then
        raise exception 'Invalid workspace update' using errcode = '22023';
    end if;

    if p_expected = 0 then
        insert into public.studyflow_workspaces (workspace, revision, ciphertext)
        values (p_workspace, 1, p_ciphertext)
        on conflict (workspace) do nothing;
    else
        update public.studyflow_workspaces w
        set revision = p_expected + 1, ciphertext = p_ciphertext
        where w.workspace = p_workspace and w.revision = p_expected;
    end if;

    return found;
end;
$$;

revoke all on function public.studyflow_read(text) from public, authenticated;
revoke all on function public.studyflow_write(text, bigint, text) from public, authenticated;
grant execute on function public.studyflow_read(text) to anon;
grant execute on function public.studyflow_write(text, bigint, text) to anon;

create table if not exists public.studyflow_shares (
    workspace text primary key check (workspace ~ '^[0-9a-f]{64}$'),
    owner_key text not null check (owner_key ~ '^[0-9a-f]{64}$'),
    revoked boolean not null default false,
    ciphertext text not null check (length(ciphertext) between 40 and 3000000)
);

alter table public.studyflow_shares enable row level security;
revoke all on public.studyflow_shares from public, anon, authenticated;

create or replace function public.studyflow_share_read(p_workspace text)
returns table (ciphertext text)
language sql stable security definer set search_path = ''
as $$
    select s.ciphertext from public.studyflow_shares s
    where s.workspace = p_workspace and not s.revoked and p_workspace ~ '^[0-9a-f]{64}$';
$$;

create or replace function public.studyflow_share_write(p_workspace text, p_owner text, p_ciphertext text)
returns boolean
language plpgsql security definer set search_path = ''
as $$
begin
    if p_workspace is null or p_workspace !~ '^[0-9a-f]{64}$' or
       p_owner is null or p_owner !~ '^[0-9a-f]{64}$' or
       p_ciphertext is null or length(p_ciphertext) not between 40 and 3000000 then
        raise exception 'Invalid share update' using errcode = '22023';
    end if;

    insert into public.studyflow_shares as s (workspace, owner_key, ciphertext)
    values (p_workspace, p_owner, p_ciphertext)
    on conflict (workspace) do update set ciphertext = excluded.ciphertext
    where s.owner_key = excluded.owner_key and not s.revoked;
    return found;
end;
$$;

create or replace function public.studyflow_share_revoke(p_workspace text, p_owner text)
returns void
language sql security definer set search_path = ''
as $$
    insert into public.studyflow_shares as s (workspace, owner_key, revoked, ciphertext)
    select p_workspace, p_owner, true, repeat('0', 40)
    where p_workspace ~ '^[0-9a-f]{64}$' and p_owner ~ '^[0-9a-f]{64}$'
    on conflict (workspace) do update set revoked = true, ciphertext = repeat('0', 40)
    where s.owner_key = excluded.owner_key;
$$;

revoke all on function public.studyflow_share_read(text) from public, authenticated;
revoke all on function public.studyflow_share_write(text, text, text) from public, authenticated;
revoke all on function public.studyflow_share_revoke(text, text) from public, authenticated;
grant execute on function public.studyflow_share_read(text) to anon;
grant execute on function public.studyflow_share_write(text, text, text) to anon;
grant execute on function public.studyflow_share_revoke(text, text) to anon;
commit;

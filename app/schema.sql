create table if not exists payments (
  id text primary key,
  merchant text not null,
  amount integer not null,
  status text not null,
  created_by text not null,
  created_at text not null,
  memo text,
  reviewed_by text,
  reviewed_at text
);

create table if not exists audit_events (
  id text primary key,
  time text not null,
  actor text not null,
  role text not null,
  action text not null,
  result text not null,
  detail text not null
);

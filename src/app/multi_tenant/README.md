# Multi-tenant service with user access and a periodic background task

A single-file service for the `MULTI_TENANT` isolation: one instance serves all subscribed tenants.

- REST endpoints that act on behalf of the calling user (`/user`, `/events/{device_id}`),
  so the user's own permissions apply.
- A background task that processes the devices of every subscribed tenant periodically,
  using the service user of each tenant.
- Health endpoint for the liveness probe (`/health`).

Choose `MULTI_TENANT` as isolation when starting from this example.

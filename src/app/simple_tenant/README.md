# Per-tenant service with user access and a periodic background task

A single-file service for the `PER_TENANT` isolation: one instance per subscribed tenant.

- REST endpoints that act on behalf of the calling user (`/user`, `/events/{device_id}`),
  so the user's own permissions apply.
- A background task that processes all devices of the tenant periodically, using the
  service's own user.
- Health endpoint for the liveness probe (`/health`).

Choose `PER_TENANT` as isolation when starting from this example.

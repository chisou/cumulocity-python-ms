# Multi-tenant service with Notification 2.0 subscriptions

A single-file service for the `MULTI_TENANT` isolation that reacts to events of every tenant.

- Notices when a tenant subscribes to or unsubscribes from the service.
- Creates a Notification 2.0 subscription for alarms in each subscribed tenant, listens to
  it, and removes it again when the tenant unsubscribes or the service stops.
- A REST endpoint listing the open alarms of the calling user's tenant (`/alarms`).

Needs the `ROLE_NOTIFICATION_2_ADMIN` role (already in `src/cumulocity.json`).
Choose `MULTI_TENANT` as isolation when starting from this example.

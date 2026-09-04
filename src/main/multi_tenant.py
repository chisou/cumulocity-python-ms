# Copyright (c) 2026 Christoph Souris

import logging
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import FastAPI, Request
from pyc8y import MultiTenantCumulocityApp
from pyc8y.model import Subscription
from pyc8y.notification2 import Listener
from pyc8y.notification2.listener import Message

# A multi-tenant Cumulocity application that, for every subscribed tenant,
# creates a Notification 2.0 subscription for alarms raised on any of the
# tenant's devices and logs them. Subscriptions are set up when a tenant
# subscribes and torn down when it unsubscribes or the service shuts down.

# override=True: the MS service user must win over any admin credentials
# already present in the environment (e.g. from an active c8y-cli session).
load_dotenv(".env-ms", override=True)

logging.basicConfig(level=logging.DEBUG, format="%(asctime)s %(levelname)s - %(name)s - %(message)s")
log = logging.getLogger("service")

SUBSCRIPTION_NAME = "sampleAlarmSubscription"


async def log_alarm(message: Message) -> None:
    """Log every alarm notification as it comes in."""
    log.debug("Alarm raised: %s", message.json)


@asynccontextmanager
async def lifespan(app: FastAPI):

    app.state.bootstrap_app = MultiTenantCumulocityApp()
    app.state.alarm_subscriptions = {}
    app.state.alarm_listeners = {}

    async def on_tenant_subscribed(tenant_id: str) -> None:
        """Subscribe to alarms of all devices of a newly subscribed tenant."""
        client = await app.state.bootstrap_app.get_tenant_instance(tenant_id)
        subscriptions = await client.subscriptions.get_all(subscription=SUBSCRIPTION_NAME)
        if subscriptions:
            # TODO: Better recreate, proper cleanup
            subscription = subscriptions[0]
        else:
            subscription = await Subscription(
                client,
                name=SUBSCRIPTION_NAME,
                context=Subscription.Context.TENANT,
                api_filter=[Subscription.ApiFilter.ALARMS],
            ).create()

        listener = Listener(client, subscription_name=SUBSCRIPTION_NAME)
        listener.start(log_alarm)

        app.state.alarm_subscriptions[tenant_id] = subscription
        app.state.alarm_listeners[tenant_id] = listener
        log.info("Subscribed to alarms for tenant '%s'.", tenant_id)

    async def on_tenant_unsubscribed(tenant_id: str) -> None:
        """Remove the alarm subscription of a tenant that unsubscribed."""
        listener = app.state.alarm_listeners.pop(tenant_id, None)
        if listener:
            listener.stop()
            await listener.wait()

        subscription = app.state.alarm_subscriptions.pop(tenant_id, None)
        if subscription:
            await subscription.delete()

        log.info("Removed alarm subscription for tenant '%s'.", tenant_id)

    subscription_listener = app.state.bootstrap_app.create_subscription_listener()
    subscription_listener.on_add(on_tenant_subscribed)
    subscription_listener.on_remove(on_tenant_unsubscribed)
    subscription_listener.start()

    yield

    subscription_listener.stop()
    for tenant_id in list(app.state.alarm_listeners):
        await on_tenant_unsubscribed(tenant_id)
    await app.state.bootstrap_app.close()


app = FastAPI(lifespan=lifespan)


@app.get("/health")
async def get_health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/alarms")
async def get_alarms(request: Request) -> list[dict]:
    """List all open (i.e. not yet cleared) alarms of the calling tenant."""
    client = await app.state.bootstrap_app.get_tenant_instance(headers=request.headers, cookies=request.cookies)
    alarms = await client.alarms.get_all(resolved="false", limit=None)
    return [{"id": a.id, "type": a.type, "text": a.text, "severity": a.severity, "status": a.status} for a in alarms]

# Copyright (c) 2024 Cumulocity GmbH

from __future__ import annotations

from http.client import HTTPConnection
import logging
import os

from apscheduler.schedulers.background import BackgroundScheduler
from dotenv import load_dotenv
from flask import Flask, request, jsonify

from c8y_api._base_api import UnauthorizedError
from c8y_api.app import MultiTenantCumulocityApp
from c8y_tk.app import SubscriptionListener


# A multi-tenant aware Cumulocity application can be created just like this.
# The bootstrap authentication information is read from the standard
# Cumulocity environment variables that are injected into the Docker
# container.

# The MultiTenantCumulocityApp class is not a CumulocityApi instance (in
# contrast to SimpleCumulocityApp), it acts as a factory to provide
# specific CumulocityApi instances for subscribed tenants  and users.

# load environment from a .env if present
load_dotenv()

# enable full logging for requests
HTTPConnection.debuglevel = 1
logging.basicConfig()
logging.getLogger().setLevel(logging.INFO)
requests_log = logging.getLogger("requests.packages.urllib3")
requests_log.setLevel(logging.INFO)
requests_log.propagate = True

# global data
subscribed_tenants = set()

# ------------------------------------------------------------------------

def add_subscriber(tenant):
    """Callback, invoked by subscription listener on new subscriber tenants.

    This only updates the internal list of subscribed tenants.
    """
    global subscribed_tenants
    subscribed_tenants = subscribed_tenants | {tenant}
    logging.info(f"Tenant '{tenant}' added.")


def remove_subscriber(tenant):
    """Callback, invoked by subscription listener when tenants unsubscribe.

    This only updates the internal list of subscribed tenants.
    """
    global subscribed_tenants
    subscribed_tenants = subscribed_tenants - {tenant}
    logging.info(f"Tenant '{tenant}' removed.")


def process_subscribers():
    """Background task, processing data of all current subscribing tenants."""
    global subscribed_tenants
    global c8yapp
    for tenant in subscribed_tenants:
        logging.info(f"Processing tenant '{tenant}' ...")
        tenant_c8y = c8yapp.get_tenant_instance(tenant_id=tenant)
        logging.info(f"  Tenant {tenant} devices: {tenant_c8y.device_inventory.get_count()}")

# --- Application --------------------------------------------------------

# initialize cumulocity
c8yapp = MultiTenantCumulocityApp()
logging.info("CumulocityApp initialized.")
c8y_bootstrap = c8yapp.bootstrap_instance
logging.info(f"Bootstrap: {c8y_bootstrap.base_url}, Application Key: {c8y_bootstrap.application_key}, Tenant: {c8y_bootstrap.tenant_id}, User:{c8y_bootstrap.username}")
c8y_vars = [f'{k}={v}' for k, v in os.environ.items() if k.startswith('C8Y_')]
for x in c8y_vars:
    logging.info(x)

# setup subscription listener
subscription_listener = SubscriptionListener(app=c8yapp, polling_interval=60)
subscription_listener.add_callback(add_subscriber, blocking=True, when="added")
subscription_listener.add_callback(remove_subscriber, blocking=True, when="removed")

# setup background task
process_subscribers_scheduler = BackgroundScheduler()
process_subscribers_scheduler.add_job(func=process_subscribers, trigger="interval", seconds=300)

# --- Flask --------------------------------------------------------------

# setup Flask
webapp = Flask(__name__)

@webapp.route("/health")
def health():
    """Return dummy health string."""
    return jsonify({'status': 'ok'})


@webapp.route("/debug")
def debug():
    """Return debug information."""
    return jsonify({
        'headers': dict(request.headers),
        'cookies': dict(request.cookies),
        'subscribers': list(subscribed_tenants),
    })


@webapp.route("/tenant")
def tenant_info():
    """Return subscribed tenant's ID, username and devices it has access to."""
    # The subscribed tenant's credentials (to access Cumulocity and to access
    # the microservice) are part of the inbound request's headers. This is
    # resolved automatically when using the get_tenant_instance function.
    c8y = c8yapp.get_tenant_instance(headers=request.headers, cookies=request.cookies)
    logging.info(f"Obtained tenant instance: tenant: {c8y.tenant_id}, user: {c8y.username}, pass: {c8y.auth.password}")
    # If the tenant ID is known (e.g. from URL) it can be given directly
    # like this:
    # c8y = c8yapp.get_tenant_instance(tenant_id='t12345')
    tenant_json = {'tenant_id': c8y.tenant_id,
                   'base_url': c8y.base_url,
                   'username': c8y.username}
    devices_json = [{'name': d.name,
                     'id': d.id,
                     'type': d.type} for d in c8y.device_inventory.get_all()]
    info_json = {'tenant': tenant_json,
                 'devices': devices_json}
    return jsonify(info_json)


@webapp.route("/user")
def user_info():
    """Return user's tenant, username and devices they have access to."""
    # The user's credentials (to access Cumulocity and to access the
    # microservice) are part of the inbound request's headers. This is
    # resolved automatically when using the get_user_instance function.
    # Note: the user connections are cached, hence it can be possible to
    # receive an outdated, no longer valid connection. The corresponding
    # UnauthorizedError must be caught and dealt with.
    for _ in range(2):
        c8y = c8yapp.get_user_instance(headers=request.headers, cookies=request.cookies)
        try:
            logging.info(f"Obtained user instance: tenant: {c8y.tenant_id}, user: {c8y.username}")
            devices_json = [{'name': d.name,
                             'id': d.id,
                             'type': d.type} for d in c8y.device_inventory.get_all()]
            info_json = {'username': c8y.username,
                         'devices': devices_json}
            return jsonify(info_json)
        except UnauthorizedError:
            c8yapp.clear_user_cache(c8y.username)
    raise RuntimeError("Unable to obtain a valid user scope connection!")


# === MAIN PROGRAM =======================================================

process_subscribers_scheduler.start()
subscription_listener.start()

webapp.run(host='0.0.0.0', port=80)

subscription_listener.stop()  # signal stop
# wait for scheduler and listener to finish
process_subscribers_scheduler.shutdown(wait=True)
subscription_listener.shutdown(timeout=None)

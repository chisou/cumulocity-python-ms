# Copyright (c) 2024 Cumulocity GmbH

from __future__ import annotations

import logging
import os

from apscheduler.schedulers.background import BackgroundScheduler
from dotenv import load_dotenv
from flask import Flask, request, jsonify

from c8y_api.app import MultiTenantCumulocityApp
from c8y_tk.app import SubscriptionListener


# A multi-tenant aware Cumulocity application can be created just like this.
# The bootstrap authentication information is read from the standard
# Cumulocity environment variables that are injected into the Docker
# container.

# The MultiTenantCumulocityApp class is not a CumulocityApi instance (in
# contrast to SimpleCumulocityApp), it acts as a factory to provide
# specific CumulocityApi instances for subscribed tenants  and users.

load_dotenv('.env-ms')  # load environment from a file if present / enables local testing

logging.basicConfig(level=logging.DEBUG, format='%(asctime)s %(levelname)s - %(name)s - %(threadName)s - %(message)s')
logging.getLogger("urllib3").setLevel(logging.DEBUG)

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
c8yapp.clear_user_cache()
logging.info("CumulocityApp initialized.")
c8y_bootstrap = c8yapp.bootstrap_instance
c8y_bootstrap.device_inventory.get_count()
logging.info(f"Bootstrap: {c8y_bootstrap.base_url}, Application Key: {c8y_bootstrap.application_key}, Tenant: {c8y_bootstrap.tenant_id}, User:{c8y_bootstrap.username}")
c8y_vars = [f'{k}={v}' for k, v in os.environ.items() if k.startswith('C8Y_')]
for x in c8y_vars:
    logging.info(x)

# setup subscription listener
subscription_listener = SubscriptionListener(app=c8yapp, polling_interval=60)
subscription_listener.add_callback(add_subscriber, blocking=False, when="added")
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


@webapp.route("/subscribers")
def subscriber_info():
    """Return the list of subscribed tenants.

    Only bootstrap tenant users are allowed to access this.
    """
    # verify that current user has access
    c8y = c8yapp.get_user_instance(headers=request.headers, cookies=request.cookies)
    if c8y.tenant_id != c8y_bootstrap.tenant_id:
        jsonify({'error': "Only allowed for the provider tenant."}), 403
    # create tenant connection and collect info
    subscribers = []
    for tenant_id in subscribed_tenants:
        c8y = c8yapp.get_tenant_instance(tenant_id=tenant_id)
        subscribers.append({
            'tenant_id': c8y.tenant_id,
            'base_url': c8y.base_url,
            'num_devices': c8y.device_inventory.get_count(),
        })
    return jsonify({'subscribers': subscribers})


@webapp.route("/user")
def user_info():
    """Return user's tenant, username and devices they have access to."""
    c8y = c8yapp.get_user_instance(headers=request.headers, cookies=request.cookies)
    logging.info(f"Obtained user instance: tenant: {c8y.tenant_id}, user: {c8y.username}")
    devices_json = [{'name': d.name,
                     'id': d.id,
                     'type': d.type} for d in c8y.device_inventory.get_all()]
    info_json = {'username': c8y.username,
                 'devices': devices_json}
    return jsonify(info_json)


# === MAIN PROGRAM =======================================================

process_subscribers_scheduler.start()
subscription_listener.start()

webapp.run(host='0.0.0.0', port=80)

subscription_listener.stop()  # signal stop
# wait for scheduler and listener to finish
process_subscribers_scheduler.shutdown(wait=True)
subscription_listener.shutdown(timeout=None)

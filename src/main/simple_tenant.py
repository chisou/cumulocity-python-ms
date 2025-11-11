# Copyright (c) 2025 Cumulocity GmbH

from __future__ import annotations

import logging
import os
from http.client import HTTPConnection

from apscheduler.schedulers.background import BackgroundScheduler
from dotenv import load_dotenv
from flask import Flask, jsonify, request
from inputimeout import inputimeout, TimeoutOccurred

from c8y_api.app import SimpleCumulocityApp
from c8y_api.model import Celsius, Device, Measurement, Operation

# A simple (per tenant) Cumulocity application can be created just like this.
# The authentication information is read from the standard Cumulocity
# environment variables that are injected into the Docker container.

load_dotenv('.env-ms')  # load environment from a file if present / enables local testing

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s - %(name)s - %(message)s')
logging.getLogger("urllib3").setLevel(logging.DEBUG)


# --- Application --------------------------------------------------------

# initialize cumulocity
c8y = SimpleCumulocityApp()
logging.info(f"{c8y.base_url}, Tenant: {c8y.tenant_id}, User:{c8y.username}")
c8y_vars = [f'{k}={v}' for k, v in os.environ.items() if k.startswith('C8Y_')]
for x in c8y_vars:
    logging.info(x)


# setup background task
def process_devices():
    """Background task, processing all registered devices."""
    global c8y
    for device in c8y.device_inventory.get_all():
        logging.info(f"Processing device '{device.name}' ({device.id}) ...")


process_devices_scheduler = BackgroundScheduler()
process_devices_scheduler.add_job(func=process_devices, trigger="interval", seconds=300)


# --- Flask --------------------------------------------------------------

# setup Flask
webapp = Flask(__name__)

@webapp.errorhandler(403)
def forbidden(e):
    return jsonify(error=str(e)), 403


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
    })


@webapp.route("/user")
def user_info():
    """Return user's tenant, username and devices they have access to."""
    user_c8y = c8y.get_user_instance(headers=request.headers, cookies=request.cookies)
    logging.info(f"Obtained user instance: tenant: {c8y.tenant_id}, user: {c8y.username}")
    devices_json = [{'name': d.name,
                     'id': d.id,
                     'type': d.type} for d in c8y.device_inventory.get_all()]
    info_json = {'username': c8y.username,
                 'devices': devices_json}
    return jsonify(info_json)


@webapp.route("/events/<string:device_id>")
def event_info(device_id):
    # verify that device exists
    try:
        c8y.device_inventory.get(device_id)
    except KeyError:
        return jsonify({'error': f'No such device: {device_id}'}), 404

    events = [
        { "datetime": e.datetime,
          "type": e.type,
          "text": e.text,
        }
    for e in c8y.events.get_all(device_id=device_id)]
    return jsonify({'events': events})


# === MAIN PROGRAM =======================================================

process_devices_scheduler.start()
webapp.run(host='0.0.0.0', port=80)

# wait for scheduler to finish after shutdown
process_devices_scheduler.shutdown(wait=True)

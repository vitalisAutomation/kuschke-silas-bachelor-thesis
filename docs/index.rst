.. bachelor-thesis-silas-kuschke documentation master file, created by
   sphinx-quickstart on Mon Jun 22 10:10:49 2026.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

ctrlX Automation Scripts Documentation
======================================

This documentation describes the Python automation scripts used with Bosch
Rexroth ctrlX CORE devices. It covers snap deployment, offline license
installation, REST authentication, Data Layer access, and the relevant device
state transitions.

The scripts communicate with the CORE through HTTPS REST endpoints. The current
implementation disables TLS certificate verification for development devices;
this is documented as a security limitation in the API reference and should not
be used unchanged in production networks.

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   modules

Indices and search
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`

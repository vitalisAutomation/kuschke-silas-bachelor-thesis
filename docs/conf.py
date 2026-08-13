# Configuration file for the Sphinx documentation builder.
#
# For the full list of built-in configuration values, see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

import os
import sys
from pathlib import Path

# -- Path setup --------------------------------------------------------------
import os
import sys

# Hardcoded absolute paths to guarantee Sphinx autodoc finds the modules on Windows
sys.path.insert(0, r"C:\development\bachelor-thesis-silas-kuschke\ctrlx-test-app-for-deployment\backend")
sys.path.insert(0, r"C:\development\bachelor-thesis-silas-kuschke\ctrlx-app-installation-automation")
sys.path.insert(0, r"C:\development\bachelor-thesis-silas-kuschke\ctrlx-flask-app-test")
sys.path.insert(0, r"C:\development\bachelor-thesis-silas-kuschke\ctrlx-licensing-installation")


# -- Project information -----------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#project-information

project = 'bachelor-thesis-silas-kuschke'
copyright = '2026, Silas Kuschke'
author = 'Silas Kuschke'
release = '1.0.0'


# -- General configuration ---------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#general-configuration

# Added extensions to enable automatic docstring extraction and code viewing
extensions = [
    'sphinx.ext.autodoc',  # Core library to extract docstrings
    'sphinx.ext.napoleon', # Support for Google/NumPy style docstrings
    'sphinx.ext.viewcode', # Adds links to the original Python source code in HTML
]

templates_path = ['_templates']
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']


# -- Options for HTML output -------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#options-for-html-output

# Updated from 'alabaster' to 'sphinx_rtd_theme' for a professional look
html_theme = 'sphinx_rtd_theme'
html_static_path = ['_static']

# Mock external libraries so Sphinx doesn't fail to import modules when building
autodoc_mock_imports = [
    "requests",
    "flask",
    "flask_cors",
    "flask_socketio",
    "urllib3",
    "dotenv",
    "eventlet",
    "getpass",
]

"""core.graph package initializer.

This package provides the D3-based visualization helpers (in the submodule)
and proxies a few symbols from the original `core/graph.py` module so older
imports like `from core.graph import explore_users` keep working.
"""
from .visualization import generate_html, generate_html_from_files

# Load the original core/graph.py implementation dynamically and export selected names
import importlib.util
import os

_this_dir = os.path.dirname(__file__)
_candidate = os.path.abspath(os.path.join(_this_dir, '..', 'graph.py'))
if os.path.exists(_candidate):
	spec = importlib.util.spec_from_file_location('core._graph_impl', _candidate)
	_graph_impl = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(_graph_impl)

	# re-export commonly used functions from the implementation module
	explore_users = getattr(_graph_impl, 'explore_users', None)
	compute_suspicious_scores = getattr(_graph_impl, 'compute_suspicious_scores', None)
else:
	explore_users = None
	compute_suspicious_scores = None

__all__ = ["generate_html", "generate_html_from_files", "explore_users", "compute_suspicious_scores"]

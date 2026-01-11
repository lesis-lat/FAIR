import importlib.util
import os

from .visualization import generate_html, generate_html_from_files

module_dir = os.path.dirname(__file__)
graph_impl_path = os.path.abspath(os.path.join(module_dir, "..", "graph.py"))

explore_users = None
compute_suspicious_scores = None

if os.path.exists(graph_impl_path):
    spec = importlib.util.spec_from_file_location("core._graph_impl", graph_impl_path)
    graph_impl = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(graph_impl)

    explore_users = getattr(graph_impl, "explore_users", None)
    compute_suspicious_scores = getattr(graph_impl, "compute_suspicious_scores", None)

__all__ = ["generate_html", "generate_html_from_files", "explore_users", "compute_suspicious_scores"]

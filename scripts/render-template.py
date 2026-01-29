#!/usr/bin/env python3
"""
Simple Jinja2-like template renderer for workflow generation.
Handles variable substitution, conditionals, and loops.
"""

import sys
import json
from jinja2 import Environment, FileSystemLoader, select_autoescape

def main():
    if len(sys.argv) < 3:
        print("Usage: render-template.py <template_file> <variables_json>", file=sys.stderr)
        sys.exit(1)

    template_file = sys.argv[1]
    variables_json = sys.argv[2]

    # Load variables
    try:
        variables = json.loads(variables_json)
    except json.JSONDecodeError as e:
        print(f"Error parsing variables JSON: {e}", file=sys.stderr)
        sys.exit(1)

    # Set up Jinja2 environment
    import os
    template_dir = os.path.dirname(template_file)
    template_name = os.path.basename(template_file)

    env = Environment(
        loader=FileSystemLoader(template_dir),
        autoescape=select_autoescape(),
        trim_blocks=True,
        lstrip_blocks=True,
    )

    # Load and render template
    try:
        template = env.get_template(template_name)
        output = template.render(**variables)
        print(output)
    except Exception as e:
        print(f"Error rendering template: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()

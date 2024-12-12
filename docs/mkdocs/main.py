### This function delares macros which can be used in the documentation files.
import json
from pathlib import Path
from io import StringIO
from html.parser import HTMLParser
import random
import string
from textwrap import indent as indent_text
from typing import Any

current_dir = Path(__file__).parent


class MLStripper(HTMLParser):
    def __init__(self):
        super().__init__()
        self.reset()
        self.strict = False
        self.convert_charrefs = True
        self.text = StringIO()

    def handle_data(self, d):
        self.text.write(d)

    def get_data(self):
        return self.text.getvalue()


def strip_tags(html):
    s = MLStripper()
    s.feed(html)
    return s.get_data()


def define_env(env):
    # Read the versions.json file in `/lib`
    # This allows `{{ versions.drift }}` in the markdown files
    version_file = Path(__file__).parent.parent / "lib" / "versions.json"
    versions: dict[str, str] = json.loads(version_file.read_text())
    env.variables["versions"] = versions

    @env.macro
    def load_snippet(snippet_name: str, *args: str, indent: int = 0) -> str:
        """
        This macro allows to load a snippets from source files and display them in the documentation.

        The snippet_name referes to whatever the snippet is named in the source file (e.g. `setup` from  `// #docregion setup``)

        The args are a list of files to load the snippet from. (e.g 'lib/snippets/setup/database.dart.excerpt.json')

        The indent is the number of spaces to indent the snippet by. (default is 0)
        This is used when placing a snippet inside tabs.
        See the `docs` for examples where indentation is used.
        """
        files = [current_dir.parent / i for i in args]
        snippet: str = None
        for file in files:
            raw = json.loads(file.read_text())
            if snippet_name in raw:
                snippet = raw[snippet_name]
                break

        if snippet is None:
            raise f"Could not find snippet {snippet_name} in {args}"

        result = html_codeblock(snippet)

        # Add the indent to the snippet, besides for the first line which is already indented.
        return indent_text(result, indent * " ").lstrip()


def markdown_codeblock(content: str, lang: str = "") -> str:
    return f"```{lang}\n{content}\n```"


def html_codeblock(content: str) -> str:
    random_id = "".join(random.choices(string.ascii_lowercase + string.digits, k=8))

    result = f"""
/// html | div[class="highlight"]
    markdown: html
<pre id="{random_id}"><code>{content}</code></pre>
///
    """
    return result

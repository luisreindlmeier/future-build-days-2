"""Serve only public project assets; credentials and arbitrary files are never served."""
import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit

PUBLIC = {'/', '/index.html', '/projects.html', '/css/dashboard.css', '/css/glass.css', '/js/ui.js', '/js/dashboard.js', '/js/studio.js', '/js/charts.js', '/js/tree3d.js', '/js/prediction.js', '/js/learn.js', '/css/style.css', '/js/config.js', '/js/engine.js',
          '/js/ai.js', '/js/customer.js', '/js/app.js'}


class PublicAssets(SimpleHTTPRequestHandler):
    def send_head(self):
        if unquote(urlsplit(self.path).path) not in PUBLIC:
            self.send_error(404)
            return None
        return super().send_head()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', required=True)
    parser.add_argument('--port', type=int, default=5500)
    args = parser.parse_args()
    ThreadingHTTPServer(('127.0.0.1', args.port),
        lambda *a, **kw: PublicAssets(*a, directory=args.directory, **kw)).serve_forever()

compose_project = os.getenv('COMPOSE_PROJECT_NAME', os.path.basename(os.getcwd()))
# Load optional tools so they are available for manual startup in Tilt.
docker_compose('./compose.yaml', project_name=compose_project, profiles=['developer-tools'])

app_url = 'http://localhost:3000'

dc_resource(
    'postgres',
    infer_links=False,
    labels=['infrastructure'],
)

dc_resource(
    's3mock',
    infer_links=False,
    labels=['infrastructure'],
)

local_resource(
    'db-migrate',
    cmd='./scripts/db-local.sh migrate',
    deps=['atlas.hcl', 'migrations', 'scripts/db-local.sh'],
    resource_deps=['postgres'],
    labels=['infrastructure'],
)

local_resource(
    'api',
    cmd='go build -o ../.tiltbuild/api ./cmd/api',
    dir='api',
    deps=['api'],
    ignore=['api/**/*_test.go', 'api/Dockerfile', 'api/.dockerignore', 'api/schema.sql', 'api/seed.sql', 'api/queries'],
    serve_cmd='./.tiltbuild/api',
    serve_env={
        'AWS_ACCESS_KEY_ID': 'app',
        'AWS_ENDPOINT_URL_S3': 'http://127.0.0.1:9090',
        'AWS_REGION': 'us-east-1',
        'AWS_SECRET_ACCESS_KEY': 'app',
        'DATABASE_URL': '',
        'ENVIRONMENT': 'local',
        'PGDATABASE': 'app',
        'PGHOST': '127.0.0.1',
        'PGPASSWORD': 'app',
        'PGPORT': '5432',
        'PGSSLMODE': 'disable',
        'PGUSER': 'app',
        'PORT': '8080',
        'S3_BUCKET': 'app',
    },
    readiness_probe=probe(http_get=http_get_action(port=8080, host='127.0.0.1', path='/ready')),
    resource_deps=['db-migrate', 's3mock'],
    labels=['application'],
)

local_resource(
    'web',
    cmd='pnpm install --frozen-lockfile',
    dir='web',
    deps=['web/package.json', 'web/pnpm-lock.yaml', 'web/pnpm-workspace.yaml'],
    serve_cmd='pnpm dev',
    serve_dir='web',
    serve_env={'VITE_ENVIRONMENT': 'local'},
    readiness_probe=probe(http_get=http_get_action(port=3000, host='127.0.0.1', path='/')),
    links=[link(app_url, 'web')],
    labels=['application'],
)

dc_resource(
    'pgadmin',
    links=[link('http://localhost:3002', 'pgAdmin')],
    infer_links=False,
    resource_deps=['postgres'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    labels=['developer-tools'],
)

dc_resource(
    'scalar',
    links=[link('http://localhost:3001', 'scalar')],
    infer_links=False,
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    labels=['developer-tools'],
)

dc_resource(
    'chartdb',
    links=[link('http://localhost:3003', 'chartdb')],
    infer_links=False,
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    labels=['developer-tools'],
)

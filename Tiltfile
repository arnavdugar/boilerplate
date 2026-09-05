compose_project = os.getenv('COMPOSE_PROJECT_NAME', os.path.basename(os.getcwd()))

docker_compose('./compose.yaml', profiles=['developer-tools'], project_name=compose_project)

local_resource(
    'api',
    cmd='go build -o ../.tiltbuild/api ./cmd/api',
    deps=['api'],
    dir='api',
    ignore=[
        'api/**/*_test.go',
        'api/.dockerignore',
        'api/Dockerfile',
        'api/queries',
        'api/schema.sql',
        'api/seed.sql',
    ],
    labels=['application'],
    links=[link('http://localhost:8080/debug/pprof/', 'pprof')],
    readiness_probe=probe(http_get=http_get_action(host='127.0.0.1', path='/ready', port=8080)),
    resource_deps=['db-migrate', 's3mock'],
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
)

local_resource(
    'web',
    cmd='pnpm install --frozen-lockfile',
    deps=['web/package.json', 'web/pnpm-lock.yaml', 'web/pnpm-workspace.yaml'],
    dir='web',
    labels=['application'],
    links=[link('http://localhost:3000', 'web')],
    readiness_probe=probe(http_get=http_get_action(host='127.0.0.1', path='/', port=3000)),
    serve_cmd='pnpm dev',
    serve_dir='web',
    serve_env={'VITE_ENVIRONMENT': 'local'},
)

dc_resource(
    'chartdb',
    auto_init=False,
    infer_links=False,
    labels=['developer-tools'],
    links=[link('http://localhost:3001', 'chartdb')],
    trigger_mode=TRIGGER_MODE_MANUAL,
)

dc_resource(
    'pgadmin',
    auto_init=False,
    infer_links=False,
    labels=['developer-tools'],
    links=[link('http://localhost:3002', 'pgAdmin')],
    resource_deps=['postgres'],
    trigger_mode=TRIGGER_MODE_MANUAL,
)

dc_resource(
    'scalar',
    auto_init=False,
    infer_links=False,
    labels=['developer-tools'],
    links=[link('http://localhost:3003', 'scalar')],
    trigger_mode=TRIGGER_MODE_MANUAL,
)

local_resource(
    'storybook',
    auto_init=False,
    labels=['developer-tools'],
    links=[link('http://localhost:3004', 'storybook')],
    readiness_probe=probe(http_get=http_get_action(host='127.0.0.1', path='/index.json', port=3004)),
    resource_deps=['web'],
    serve_cmd='pnpm storybook',
    serve_dir='web',
    trigger_mode=TRIGGER_MODE_MANUAL,
)

local_resource(
    'db-migrate',
    cmd='./scripts/db-local.sh migrate',
    deps=['atlas.hcl', 'migrations', 'scripts/db-local.sh'],
    labels=['infrastructure'],
    resource_deps=['postgres'],
)

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

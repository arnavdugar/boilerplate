env "app" {
  src = "file://api/schema.sql"
  url = urlqueryset(getenv("DATABASE_URL"), "search_path", "public")
  dev = "docker://postgres/18-alpine/dev?search_path=public"

  migration {
    dir              = "file://migrations"
    revisions_schema = "atlas_schema_revisions"
  }
}

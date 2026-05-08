-- 마이그레이션 001: 크로마이핑 팩 마켓플레이스 테이블 생성
-- 적용: psql -f 001_create_pack_tables.sql
-- 롤백: psql -f rollback/001_drop_pack_tables.sql

BEGIN;

-- 본 스키마는 schema.sql 참조
\i schema.sql

-- 마이그레이션 기록 (cromaizing.com에 schema_migrations 테이블 있다면)
-- INSERT INTO schema_migrations (version, applied_at)
-- VALUES ('001_create_pack_tables', NOW());

COMMIT;

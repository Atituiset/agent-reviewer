BEGIN TRANSACTION;
CREATE TABLE memories (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'quarantine',
  content TEXT NOT NULL,
  modules TEXT NOT NULL,
  bound_paths TEXT NOT NULL,
  evidence TEXT NOT NULL,
  created_at TEXT NOT NULL,
  reviewed_by TEXT,
  reviewed_at TEXT
);
INSERT INTO "memories" VALUES('mem-20260826091557595329','review_finding','active','文件尾追加新函数先核对上一函数是否闭合——stack/nas/src/nas_messages.cpp:29 因丢失 decode 收尾} 致嵌套定义编译失败','["stack/nas/src/*.cpp"]','["stack/nas/src/nas_messages.cpp"]','{"review_artifact": "ad5ea812"}','2026-08-26T09:15:57+00:00','human-mde','2026-08-26T09:17:36+00:00');
INSERT INTO "memories" VALUES('mem-20260826091557636234','review_finding','quarantine','裸 malloc 后每条 early-return 必须先释放——stack/nas/src/nas_messages.cpp:35 与 :38 泄漏 frame','["stack/nas/src/*.cpp"]','["stack/nas/src/nas_messages.cpp"]','{"review_artifact": "ad5ea812"}','2026-08-26T09:15:57+00:00',NULL,NULL);
INSERT INTO "memories" VALUES('mem-20260826091557675740','review_finding','quarantine','malloc 返回值判空后再写入——stack/nas/src/nas_messages.cpp:33 未检查即作 memcpy 目标','["stack/nas/src/*.cpp"]','["stack/nas/src/nas_messages.cpp"]','{"review_artifact": "ad5ea812"}','2026-08-26T09:15:57+00:00',NULL,NULL);
INSERT INTO "memories" VALUES('mem-20260826091557715751','review_finding','quarantine','试验脚手架不得驻留产品源目录——stack/nas/src/nas_messages.cpp:27 零调用无声明','["stack/nas/src/*.cpp"]','["stack/nas/src/nas_messages.cpp"]','{"review_artifact": "ad5ea812"}','2026-08-26T09:15:57+00:00',NULL,NULL);
COMMIT;

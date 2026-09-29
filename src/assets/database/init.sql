-- 仅在本地数据库不存在时执行；不用于 APP 升级或内容资源更新。
-- 每条语句以行末分号结束；不使用触发器或跨行字符串。
-- 基础配置由字段 DEFAULT 提供，用户身份及设备信息在首次安装时生成。
-- 所有主键 id 显式非空；表间关系由应用字段关联处理，不使用数据库外键。

-- 基础五表来自 resources/database/data.sqlite；不含内容或用户存量数据。

CREATE TABLE `yzc_content` (
  `id` varchar(64) NOT NULL,
  `textbook_id` varchar(64) NULL DEFAULT NULL,
  `unit_id` varchar(64) NULL DEFAULT NULL,
  `lessons_id` varchar(64) NULL DEFAULT NULL,
  `lesson` varchar(64) NULL DEFAULT NULL,
  `category` varchar(64) NULL DEFAULT NULL,
  `role` varchar(64) NULL DEFAULT NULL,
  `content` varchar(1000) NULL DEFAULT NULL,
  `definition` varchar(1000) NULL DEFAULT NULL,
  `org` varchar(64) NULL DEFAULT NULL,
  `phonetic` varchar(1000) NULL DEFAULT NULL,
  `phonetic_zh` varchar(1000) NULL DEFAULT NULL,
  `sort` int NULL DEFAULT NULL,
  `jlpt` varchar(64) NULL DEFAULT NULL,
  `rate` varchar(64) NULL DEFAULT NULL,
  `ver` varchar(64) NULL DEFAULT NULL,
  `media_type` varchar(32) NOT NULL DEFAULT 'text',
  `media_src` text NULL,
  `media_config` text NULL,
  PRIMARY KEY (`id`)
);

CREATE TABLE `yzc_lessons` (
  `id` varchar(64) NOT NULL,
  `textbook_id` varchar(64) NULL DEFAULT NULL,
  `unit_id` varchar(64) NULL DEFAULT NULL,
  `num` int NULL DEFAULT NULL,
  `lesson` varchar(64) NULL DEFAULT NULL,
  `title` varchar(200) NULL DEFAULT NULL,
  `sub_title` varchar(200) NULL DEFAULT NULL,
  `definition` varchar(200) NULL DEFAULT NULL,
  `sub_definition` varchar(200) NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
);

CREATE TABLE `yzc_textbook` (
  `id` varchar(64) NOT NULL,
  `publisher` varchar(200) NULL DEFAULT NULL,
  `textbook` varchar(64) NULL DEFAULT NULL,
  `volume` varchar(64) NULL DEFAULT NULL,
  `lvl` varchar(64) NULL DEFAULT '1',
  `descr` varchar(255) NULL DEFAULT '',
  `sort` int NULL DEFAULT NULL,
  `jlpt` varchar(64) NULL DEFAULT '',
  `rate` varchar(64) NULL DEFAULT NULL,
  `ver` varchar(64) NULL DEFAULT NULL,
  `cover` varchar(1000) NULL DEFAULT NULL,
  `sfky` varchar(32) NULL DEFAULT NULL,
  `resource_file` varchar(255) NULL DEFAULT NULL,
  `sha256` varchar(64) NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
);

CREATE TABLE `yzc_unit` (
  `id` varchar(64) NOT NULL,
  `textbook_id` varchar(64) NULL DEFAULT NULL,
  `num` int NULL DEFAULT NULL,
  `title` varchar(200) NULL DEFAULT NULL,
  `content` varchar(1000) NULL DEFAULT NULL,
  `definition` varchar(1000) NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
);

CREATE TABLE `yzc_words` (
  `id` varchar(64) NOT NULL,
  `textbook_id` varchar(64) NULL DEFAULT NULL,
  `unit_id` varchar(64) NULL DEFAULT NULL,
  `lessons_id` varchar(64) NULL DEFAULT NULL,
  `lesson` varchar(64) NULL DEFAULT NULL,
  `kana` varchar(64) NULL DEFAULT NULL,
  `kanji` varchar(64) NULL DEFAULT NULL,
  `pos` varchar(64) NULL DEFAULT NULL,
  `definition` varchar(64) NULL DEFAULT NULL,
  `word` varchar(64) NULL DEFAULT NULL,
  `phonetic` varchar(1000) NULL DEFAULT NULL,
  `phonetic_zh` varchar(1000) NULL DEFAULT NULL,
  `link` varchar(1000) NULL DEFAULT NULL,
  `synonyms` varchar(255) NULL DEFAULT NULL,
  `antonyms` varchar(255) NULL DEFAULT NULL,
  `sort` int NULL DEFAULT NULL,
  `jlpt` varchar(64) NULL DEFAULT NULL,
  `rate` varchar(64) NULL DEFAULT NULL,
  `ver` varchar(64) NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
);

CREATE INDEX `yzc_content_idx_category` ON `yzc_content` (`category` ASC);

CREATE INDEX `yzc_content_idx_lesson` ON `yzc_content` (`lesson` ASC);

CREATE INDEX `yzc_content_idx_lessons_id` ON `yzc_content` (`lessons_id` ASC);

CREATE INDEX `yzc_content_idx_textbook_id` ON `yzc_content` (`textbook_id` ASC);

CREATE INDEX `yzc_content_idx_unit_id` ON `yzc_content` (`unit_id` ASC);

CREATE INDEX `yzc_lessons_idx_lesson` ON `yzc_lessons` (`lesson` ASC);

CREATE INDEX `yzc_unit_idx_textbook_id` ON `yzc_unit` (`textbook_id` ASC);

CREATE INDEX `yzc_words_idx_definition` ON `yzc_words` (`definition` ASC);

CREATE INDEX `yzc_words_idx_jlpt` ON `yzc_words` (`jlpt` ASC);

CREATE INDEX `yzc_words_idx_lesson` ON `yzc_words` (`lesson` ASC);

CREATE INDEX `yzc_words_idx_lessons_id` ON `yzc_words` (`lessons_id` ASC);

CREATE INDEX `yzc_words_idx_sort` ON `yzc_words` (`sort` ASC);

CREATE INDEX `yzc_words_idx_textbook_id` ON `yzc_words` (`textbook_id` ASC);

CREATE INDEX `yzc_words_idx_unit_id` ON `yzc_words` (`unit_id` ASC);

CREATE INDEX `yzc_words_idx_word` ON `yzc_words` (`word` ASC);

-- APP 自有结构；内容包不能执行或覆盖这些定义。
CREATE TABLE yzc_user (
 id varchar(64) NOT NULL PRIMARY KEY, name varchar(200),
 device_type varchar(64), device_model varchar(200), os_name varchar(64), os_ver varchar(64),
 app_ver varchar(64), app_build varchar(64), type varchar(64) DEFAULT 'local',
 lvl int DEFAULT 0, email varchar(255), email_verify_time bigint,
 status varchar(64) DEFAULT 'active', create_time bigint,
 update_time bigint, last_active_time bigint
);
CREATE TABLE yzc_user_device (
 id varchar(64) NOT NULL PRIMARY KEY, user_id varchar(64),
 installation_id varchar(64), device_type varchar(64), device_model varchar(200),
 os_name varchar(64), os_ver varchar(64), app_ver varchar(64), app_build varchar(64),
 create_time bigint, update_time bigint, last_active_time bigint
);
CREATE TABLE yzc_local_session (
 id varchar(64) NOT NULL PRIMARY KEY, user_id varchar(64),
 installation_id varchar(64), update_time bigint
);
CREATE TABLE yzc_user_setting (
 id varchar(64) NOT NULL PRIMARY KEY, user_id varchar(64),
 onboarding int DEFAULT 0,
 daily_goal int DEFAULT 10,
 theme varchar(64) DEFAULT 'system',
 playback_speed int DEFAULT 10,
 show_source int DEFAULT 1,
 show_ruby int DEFAULT 1,
 show_definition int DEFAULT 1,
 font_scale int DEFAULT 0,
 create_time bigint, update_time bigint
);
CREATE TABLE yzc_user_position (
 id varchar(64) NOT NULL PRIMARY KEY, user_id varchar(64),
 textbook_id varchar(64), last_textbook_id varchar(64), lessons_id varchar(64), lesson varchar(64),
 textbook varchar(64), title varchar(200), open_time bigint, create_time bigint, update_time bigint
);
-- 每本内容分别记忆阅读位置；关系由应用代码维护。
CREATE TABLE yzc_user_book_position (
 user_id TEXT NOT NULL,
 textbook_id TEXT NOT NULL,
 lessons_id TEXT,
 open_time INTEGER,
 PRIMARY KEY (user_id, textbook_id)
);
CREATE TABLE yzc_user_learn (
 id varchar(64) NOT NULL PRIMARY KEY, user_id varchar(64),
 textbook_id varchar(64), unit_id varchar(64), lessons_id varchar(64),
 lesson varchar(64), category varchar(64),
 textbook varchar(64), title varchar(200), complete_time bigint,
 create_time bigint, update_time bigint
);
CREATE TABLE yzc_user_practice (
 id varchar(64) NOT NULL PRIMARY KEY, user_id varchar(64),
 type varchar(64), textbook_id varchar(64), lessons_id varchar(64),
 start_time bigint, end_time bigint, status varchar(64),
 create_time bigint, update_time bigint
);
CREATE TABLE yzc_user_question (
 id varchar(64) NOT NULL PRIMARY KEY, user_id varchar(64),
 textbook_id varchar(64), lessons_id varchar(64), question_id varchar(64),
 ver varchar(64), type varchar(64), relation varchar(64),
 content text, definition text, answer varchar(64),
 textbook varchar(64), title varchar(200), create_time bigint, update_time bigint,
 options text,
 media_json text NULL
);
CREATE TABLE yzc_user_practice_item (
 id varchar(64) NOT NULL PRIMARY KEY, user_id varchar(64),
 practice_id varchar(64), question_id varchar(64), sort int,
 answer varchar(64), correct int, duration bigint, answer_time bigint,
 self_rating varchar(16), retry_of varchar(64),
 create_time bigint, update_time bigint
);
CREATE TABLE yzc_user_review (
 id varchar(64) NOT NULL PRIMARY KEY, user_id varchar(64),
 textbook_id varchar(64), question_id varchar(64), snapshot_id varchar(64),
 lvl int DEFAULT 0, interval_days int DEFAULT 0,
 mistake int DEFAULT 0, review_time bigint, answer_time bigint,
 create_time bigint, update_time bigint
);
CREATE TABLE yzc_user_study (
 id varchar(64) NOT NULL PRIMARY KEY, user_id varchar(64),
 event_key varchar(200), type varchar(64), textbook_id varchar(64), lessons_id varchar(64),
 practice_id varchar(64), item_id varchar(64), study_time bigint, study_date varchar(10),
 utc_offset int, create_time bigint, update_time bigint
);
CREATE TABLE yzc_resource (
 id varchar(64) NOT NULL PRIMARY KEY, textbook_id varchar(64),
 folder varchar(64), file varchar(255), url varchar(1000),
 size bigint, sha256 varchar(64), update_time bigint
);
CREATE TABLE yzc_resource_install (
 id varchar(64) NOT NULL PRIMARY KEY, textbook_id varchar(64),
 folder varchar(64),
 status varchar(64), job_id varchar(64), install_time bigint
);
CREATE TABLE yzc_resource_job (
 id varchar(64) NOT NULL PRIMARY KEY, textbook_id varchar(64), folder varchar(64),
 phase varchar(64),
 staging varchar(1000), backup varchar(1000), audio_ready int DEFAULT 0,
 had_audio int DEFAULT 0, error varchar(1000), create_time bigint, update_time bigint
);
CREATE TABLE yzc_resource_operation (
 id varchar(64) NOT NULL PRIMARY KEY, textbook_id varchar(64),
 action varchar(16),
 status varchar(16),
 folder varchar(64), sha256 varchar(64), phase varchar(64),
 error text, create_time bigint, update_time bigint, finish_time bigint
);
CREATE INDEX yzc_resource_operation_idx_book_time ON yzc_resource_operation(textbook_id,create_time,id);
CREATE INDEX yzc_resource_operation_idx_status ON yzc_resource_operation(status,action);
CREATE TABLE "yzc_grammar"
(
    id                 varchar(64) NOT NULL
        primary key,
    textbook_id        varchar(64),
    unit_id            varchar(64),
    lessons_id         varchar(64),
    lesson             varchar(64),
    content            text,
    definition         text,
    type               varchar(100),
    connection         text,
    example            text,
    example_definition text,
    tip                text,
    sort               int,
    ver                varchar(64),
    pid                varchar(64),
    pair_id            varchar(64)
);
CREATE TABLE yzc_ai_question (
 id varchar(64) NOT NULL PRIMARY KEY,
 textbook_id varchar(64),
 unit_id varchar(64),
 lessons_id varchar(64),
 question text,
 options text,
 answer varchar(64),
 descr text,
 lesson varchar(64),
 relation varchar(64),
 jlpt varchar(64),
 ver varchar(64),
 sort int,
 media_json text NULL
);
CREATE INDEX yzc_ai_question_idx_lesson_relation ON yzc_ai_question(textbook_id,lessons_id,relation,sort);

CREATE TABLE yzc_kana (
 id varchar(64) NOT NULL PRIMARY KEY, hiragana varchar(64), katakana varchar(64),
 romaji varchar(64), content varchar(255), row_num int, column_num int,
 placeholder int DEFAULT 0
);
CREATE INDEX yzc_lessons_idx_book_unit_num ON yzc_lessons(textbook_id,unit_id,num);
CREATE INDEX yzc_words_idx_book_lesson_sort ON yzc_words(textbook_id,lessons_id,sort);
CREATE INDEX yzc_content_idx_book_lesson_sort ON yzc_content(textbook_id,lessons_id,sort);
CREATE INDEX yzc_unit_idx_book_num ON yzc_unit(textbook_id,num);
CREATE INDEX yzc_user_practice_idx_user_time ON yzc_user_practice(user_id,start_time);
CREATE INDEX yzc_user_review_idx_user_due ON yzc_user_review(user_id,review_time);
CREATE INDEX yzc_user_practice_item_retry ON yzc_user_practice_item(retry_of) WHERE retry_of IS NOT NULL;
CREATE INDEX yzc_user_study_idx_user_date ON yzc_user_study(user_id,study_date);
CREATE INDEX yzc_grammar_idx_lesson_sort ON yzc_grammar(textbook_id,lessons_id,sort);

CREATE INDEX yzc_user_device_idx_user_installation ON yzc_user_device(user_id,installation_id);
CREATE INDEX yzc_user_setting_idx_user ON yzc_user_setting(user_id);
CREATE INDEX yzc_user_position_idx_user ON yzc_user_position(user_id);
CREATE INDEX yzc_user_learn_idx_scope ON yzc_user_learn(user_id,textbook_id,lessons_id,category);
CREATE INDEX yzc_user_practice_item_idx_practice_sort ON yzc_user_practice_item(user_id,practice_id,sort);
CREATE INDEX yzc_user_review_idx_source ON yzc_user_review(user_id,textbook_id,question_id);
CREATE INDEX yzc_user_study_idx_event ON yzc_user_study(user_id,event_key);
CREATE INDEX yzc_resource_idx_book ON yzc_resource(textbook_id);
CREATE INDEX yzc_resource_idx_folder ON yzc_resource(folder);
CREATE INDEX yzc_resource_install_idx_book ON yzc_resource_install(textbook_id);
CREATE INDEX yzc_resource_install_idx_folder ON yzc_resource_install(folder);

-- 五十音基础图表：保留原有 ID、排列及占位格。
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('0_0','あ','ア','a','あさ · 早晨',0,0,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('0_1','い','イ','i','いぬ · 狗',0,1,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('0_2','う','ウ','u','うみ · 海',0,2,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('0_3','え','エ','e','えき · 车站',0,3,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('0_4','お','オ','o','おちゃ · 茶',0,4,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('1_0','か','カ','ka','かさ · 伞',1,0,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('1_1','き','キ','ki','き · 树',1,1,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('1_2','く','ク','ku','くも · 云',1,2,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('1_3','け','ケ','ke','けさ · 今早',1,3,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('1_4','こ','コ','ko','こえ · 声音',1,4,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('2_0','さ','サ','sa','さかな · 鱼',2,0,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('2_1','し','シ','shi','しお · 盐',2,1,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('2_2','す','ス','su','すし · 寿司',2,2,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('2_3','せ','セ','se','せかい · 世界',2,3,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('2_4','そ','ソ','so','そら · 天空',2,4,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('3_0','た','タ','ta','たまご · 鸡蛋',3,0,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('3_1','ち','チ','chi','ちず · 地图',3,1,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('3_2','つ','ツ','tsu','つき · 月亮',3,2,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('3_3','て','テ','te','て · 手',3,3,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('3_4','と','ト','to','とり · 鸟',3,4,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('4_0','な','ナ','na','なつ · 夏天',4,0,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('4_1','に','ニ','ni','にく · 肉',4,1,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('4_2','ぬ','ヌ','nu','いぬ · 狗',4,2,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('4_3','ね','ネ','ne','ねこ · 猫',4,3,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('4_4','の','ノ','no','のり · 海苔',4,4,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('5_0','は','ハ','ha','はな · 花',5,0,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('5_1','ひ','ヒ','hi','ひと · 人',5,1,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('5_2','ふ','フ','fu','ふね · 船',5,2,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('5_3','へ','ヘ','he','へや · 房间',5,3,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('5_4','ほ','ホ','ho','ほん · 书',5,4,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('6_0','ま','マ','ma','まち · 城镇',6,0,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('6_1','み','ミ','mi','みず · 水',6,1,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('6_2','む','ム','mu','むし · 虫',6,2,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('6_3','め','メ','me','め · 眼睛',6,3,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('6_4','も','モ','mo','もり · 森林',6,4,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('7_0','や','ヤ','ya','やま · 山',7,0,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('7_1','','','','',7,1,1);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('7_2','ゆ','ユ','yu','ゆき · 雪',7,2,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('7_3','','','','',7,3,1);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('7_4','よ','ヨ','yo','よる · 夜晚',7,4,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('8_0','ら','ラ','ra','らいねん · 明年',8,0,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('8_1','り','リ','ri','りんご · 苹果',8,1,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('8_2','る','ル','ru','さる · 猴子',8,2,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('8_3','れ','レ','re','れきし · 历史',8,3,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('8_4','ろ','ロ','ro','ろく · 六',8,4,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('9_0','わ','ワ','wa','わたし · 我',9,0,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('9_1','','','','',9,1,1);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('9_2','','','','',9,2,1);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('9_3','','','','',9,3,1);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('9_4','を','ヲ','wo','助词を',9,4,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('10_0','ん','ン','n','ほん · 书',10,0,0);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('10_1','','','','',10,1,1);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('10_2','','','','',10,2,1);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('10_3','','','','',10,3,1);
INSERT INTO yzc_kana (id,hiragana,katakana,romaji,content,row_num,column_num,placeholder) VALUES ('10_4','','','','',10,4,1);


-- JLPT：安装初始化共享题库、试卷、作答与错题表，仅创建结构。
-- JLPT 仅保留主键及主键非空约束；关系和业务校验由应用处理。
-- phonetic 保存听力音频文件名；普通索引与字段默认值保留。
CREATE TABLE "stydy_jlpt_question" (
 id TEXT NOT NULL,
 version INTEGER NOT NULL,
 schema_version TEXT,
 level TEXT,
 type_code TEXT,
 exam_section_code TEXT,
 score_section_code TEXT,
 status TEXT,
 review_status TEXT,
 difficulty_target TEXT,
 difficulty_calibrated INTEGER DEFAULT 0,
 group_id TEXT,
 group_size INTEGER DEFAULT 1,
 group_order INTEGER DEFAULT 1,
 selection_policy TEXT,
 is_jlpt_original INTEGER,
 original_exam_year INTEGER,
 original_exam_month INTEGER,
 original_exam_level TEXT,
 original_exam_number TEXT,
 authenticity_status TEXT,
 source_kind TEXT,
 source_json TEXT,
 stem_json TEXT,
 options_json TEXT,
 response_json TEXT,
 answer_json TEXT,
 explanation_json TEXT,
 material_json TEXT,
 presentation_json TEXT,
 tags_json TEXT,
 estimated_seconds INTEGER,
 content_hash TEXT,
 created_at TEXT,
 updated_at TEXT,
 phonetic TEXT,
 PRIMARY KEY(id,version)
);

CREATE TABLE "stydy_jlpt_blueprint" (
 id TEXT NOT NULL,
 version INTEGER NOT NULL,
 level TEXT,
 name TEXT,
 status TEXT,
 effective_from TEXT,
 effective_to TEXT,
 parts_json TEXT,
 quotas_json TEXT,
 scoring_json TEXT,
 selection_rules_json TEXT,
 references_json TEXT,
 created_at TEXT,
 PRIMARY KEY(id,version)
);

CREATE TABLE "stydy_jlpt_generation_job" (
 id TEXT NOT NULL PRIMARY KEY,
 user_id TEXT,
 blueprint_id TEXT,
 blueprint_version INTEGER,
 state TEXT,
 seed TEXT,
 requested_paper_count INTEGER,
 filters_json TEXT,
 checkpoint_json TEXT,
 shortage_json TEXT,
 retry_count INTEGER DEFAULT 0,
 error_code TEXT,
 error_detail TEXT,
 created_at TEXT,
 updated_at TEXT
);

CREATE TABLE "stydy_jlpt_paper" (
 id TEXT NOT NULL,
 version INTEGER NOT NULL,
 level TEXT,
 title TEXT,
 kind TEXT,
 status TEXT,
 blueprint_id TEXT,
 blueprint_version INTEGER,
 generation_job_id TEXT,
 question_count INTEGER,
 parts_json TEXT,
 type_allocation_json TEXT,
 policy_json TEXT,
 score_policy_json TEXT,
 recipe_json TEXT,
 editorial_notes_json TEXT,
 created_at TEXT,
 PRIMARY KEY(id,version)
);

CREATE TABLE "stydy_jlpt_paper_item" (
 paper_id TEXT NOT NULL,
 paper_version INTEGER NOT NULL,
 position INTEGER,
 item_id TEXT NOT NULL,
 question_id TEXT,
 question_version INTEGER,
 exam_section_code TEXT,
 score_section_code TEXT,
 group_id TEXT,
 question_snapshot_json TEXT,
 option_order_json TEXT,
 raw_points REAL DEFAULT 1,
 PRIMARY KEY(paper_id,paper_version,item_id)
);

CREATE TABLE "stydy_jlpt_attempt" (
 id TEXT NOT NULL PRIMARY KEY,
 user_id TEXT,
 entry_point TEXT,
 snapshot_json TEXT,
 progress_json TEXT,
 paper_id TEXT,
 paper_version INTEGER,
 mode TEXT,
 status TEXT,
 cursor_item_id TEXT,
 active_section_code TEXT,
 policy_snapshot_json TEXT,
 presentation_mode TEXT,
 active_elapsed_ms INTEGER DEFAULT 0,
 last_checkpoint_at TEXT,
 active_device_id TEXT,
 lock_version INTEGER DEFAULT 0,
 started_at TEXT,
 paused_at TEXT,
 submitted_at TEXT,
 assistance_summary_json TEXT DEFAULT '{}',
 created_at TEXT,
 updated_at TEXT
);

CREATE TABLE "stydy_jlpt_attempt_section" (
 attempt_id TEXT NOT NULL,
 section_code TEXT NOT NULL,
 status TEXT,
 recommended_ms INTEGER,
 active_elapsed_ms INTEGER DEFAULT 0,
 extra_time_ms INTEGER DEFAULT 0,
 current_media_item_id TEXT,
 media_position_ms INTEGER DEFAULT 0,
 playback_rate REAL DEFAULT 1,
 resume_state_json TEXT DEFAULT '{}',
 first_entered_at TEXT,
 last_left_at TEXT,
 PRIMARY KEY(attempt_id,section_code)
);

CREATE TABLE "stydy_jlpt_answer" (
 attempt_id TEXT NOT NULL,
 item_id TEXT NOT NULL,
 paper_id TEXT,
 paper_version INTEGER,
 response_json TEXT,
 first_response_json TEXT,
 result TEXT,
 awarded_raw_points REAL,
 active_elapsed_ms INTEGER DEFAULT 0,
 confidence INTEGER,
 bookmarked INTEGER DEFAULT 0,
 revision INTEGER DEFAULT 0,
 hints_seen INTEGER DEFAULT 0,
 explanation_seen INTEGER DEFAULT 0,
 transcript_seen INTEGER DEFAULT 0,
 replay_count INTEGER DEFAULT 0,
 first_answered_at TEXT,
 last_answered_at TEXT,
 PRIMARY KEY(attempt_id,item_id)
);

CREATE TABLE "stydy_jlpt_answer_event" (
 id TEXT NOT NULL PRIMARY KEY,
 attempt_id TEXT,
 item_id TEXT,
 client_event_id TEXT,
 device_id TEXT,
 sequence INTEGER,
 event_type TEXT,
 payload_json TEXT,
 occurred_at TEXT,
 received_at TEXT
);

CREATE TABLE "stydy_jlpt_score_report" (
 id TEXT NOT NULL PRIMARY KEY,
 attempt_id TEXT,
 revision INTEGER,
 status TEXT,
 scoring_method TEXT,
 scoring_policy_json TEXT,
 sections_json TEXT,
 type_breakdown_json TEXT,
 assistance_json TEXT,
 total_reference_score REAL,
 reference_outcome TEXT,
 interpretation_json TEXT,
 created_at TEXT
);

CREATE TABLE "stydy_jlpt_mistake" (
 id TEXT NOT NULL PRIMARY KEY,
 user_id TEXT,
 snapshot_json TEXT,
 question_id TEXT,
 question_version INTEGER,
 first_attempt_id TEXT,
 last_attempt_id TEXT,
 state TEXT,
 wrong_count INTEGER DEFAULT 1,
 correct_streak INTEGER DEFAULT 0,
 review_count INTEGER DEFAULT 0,
 reason_tags_json TEXT DEFAULT '[]',
 personal_note TEXT,
 next_review_at TEXT,
 last_review_at TEXT,
 schedule_json TEXT DEFAULT '{}',
 created_at TEXT,
 updated_at TEXT
);

CREATE TABLE "stydy_jlpt_review_log" (
 id TEXT NOT NULL PRIMARY KEY,
 mistake_id TEXT,
 attempt_id TEXT,
 question_version INTEGER,
 response_json TEXT,
 result TEXT,
 confidence INTEGER,
 used_assistance INTEGER DEFAULT 0,
 before_schedule_json TEXT,
 after_schedule_json TEXT,
 reviewed_at TEXT
);

CREATE TABLE "stydy_jlpt_question_note" (
 user_id TEXT NOT NULL,
 question_id TEXT NOT NULL,
 favorite INTEGER DEFAULT 0,
 note TEXT,
 tags_json TEXT DEFAULT '[]',
 updated_at TEXT,
 PRIMARY KEY(user_id,question_id)
);

CREATE TABLE "stydy_jlpt_question_feedback" (
 id TEXT NOT NULL PRIMARY KEY,
 user_id TEXT,
 question_id TEXT,
 question_version INTEGER,
 attempt_id TEXT,
 category TEXT,
 description TEXT,
 status TEXT,
 resolution TEXT,
 created_at TEXT,
 resolved_at TEXT
);

CREATE TABLE "stydy_jlpt_question_statistics" (
 question_id TEXT NOT NULL,
 question_version INTEGER NOT NULL,
 cohort TEXT NOT NULL,
 presentation_mode TEXT NOT NULL,
 first_unassisted_attempts INTEGER DEFAULT 0,
 first_unassisted_correct INTEGER DEFAULT 0,
 option_counts_json TEXT DEFAULT '{}',
 median_active_ms INTEGER,
 last_aggregated_at TEXT,
 PRIMARY KEY(question_id,question_version,cohort,presentation_mode)
);

CREATE INDEX stydy_jlpt_question_filter ON stydy_jlpt_question(level,type_code,status,review_status);

CREATE INDEX stydy_jlpt_question_group ON stydy_jlpt_question(group_id,group_order,version);

CREATE INDEX stydy_jlpt_question_origin ON stydy_jlpt_question(is_jlpt_original,original_exam_year,original_exam_month,level);

CREATE INDEX stydy_jlpt_question_content ON stydy_jlpt_question(content_hash);

CREATE INDEX stydy_jlpt_attempt_user ON stydy_jlpt_attempt(user_id,status,updated_at);

CREATE INDEX stydy_jlpt_answer_event_order ON stydy_jlpt_answer_event(attempt_id,received_at);

CREATE INDEX stydy_jlpt_mistake_due ON stydy_jlpt_mistake(user_id,state,next_review_at);

-- 原额外唯一约束改为普通索引，保留关联查询能力。
CREATE INDEX "stydy_jlpt_paper_item_lookup_1" ON "stydy_jlpt_paper_item" (paper_id,paper_version,position);
CREATE INDEX "stydy_jlpt_paper_item_lookup_2" ON "stydy_jlpt_paper_item" (paper_id,paper_version,question_id);
CREATE INDEX "stydy_jlpt_attempt_lookup_1" ON "stydy_jlpt_attempt" (id,paper_id,paper_version);
CREATE INDEX "stydy_jlpt_answer_event_lookup_1" ON "stydy_jlpt_answer_event" (attempt_id,client_event_id);
CREATE INDEX "stydy_jlpt_answer_event_lookup_2" ON "stydy_jlpt_answer_event" (attempt_id,device_id,sequence);
CREATE INDEX "stydy_jlpt_score_report_lookup_1" ON "stydy_jlpt_score_report" (attempt_id,revision);
CREATE INDEX "stydy_jlpt_mistake_lookup_1" ON "stydy_jlpt_mistake" (user_id,question_id);

-- One receipt per n1~n5 package; committed with that level's content.
-- Rebuilds the installed-only study_local.json array after interruption.
CREATE TABLE stydy_resource_install (
 id TEXT NOT NULL PRIMARY KEY,
 manifest_json TEXT,
 installed_at TEXT
);
CREATE INDEX stydy_jlpt_attempt_entry ON stydy_jlpt_attempt(user_id,entry_point,status,updated_at);

-- 通知公告：服务器正文缓存、已确认次数及当前设备的已删除记录。
CREATE TABLE yzc_notice_cache (
 source TEXT NOT NULL PRIMARY KEY,
 body TEXT NOT NULL,
 etag TEXT
);
CREATE TABLE yzc_notice_confirmation (
 notice_id TEXT NOT NULL PRIMARY KEY,
 count INTEGER NOT NULL
);
CREATE TABLE yzc_notice_dismissal (
 notice_id TEXT NOT NULL PRIMARY KEY,
 dismissed_at INTEGER NOT NULL
);

-- Local system diagnostics; independent of learning records and resource imports.
CREATE TABLE yzc_system_error (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 occurred_at INTEGER NOT NULL,
 session_id TEXT,
 user_id TEXT,
 app_version TEXT,
 platform TEXT,
 os_version TEXT,
 severity TEXT NOT NULL,
 module TEXT NOT NULL,
 operation TEXT NOT NULL,
 user_hint TEXT,
 error_type TEXT,
 error_code TEXT,
 message TEXT,
 stack_trace TEXT,
 context_json TEXT
);
CREATE INDEX yzc_system_error_time ON yzc_system_error(occurred_at DESC,id DESC);

-- Formal study features: all preferences and flashcard records live in app.sqlite.
CREATE TABLE yzc_study_listening_setting (
 user_id TEXT NOT NULL PRIMARY KEY,
 book TEXT NOT NULL DEFAULT '',
 playback_speed INTEGER NOT NULL DEFAULT 10 CHECK(playback_speed BETWEEN 5 AND 30),
 show_ruby INTEGER NOT NULL DEFAULT 1 CHECK(show_ruby IN (0,1)),
 show_source INTEGER NOT NULL DEFAULT 1 CHECK(show_source IN (0,1)),
 show_definition INTEGER NOT NULL DEFAULT 1 CHECK(show_definition IN (0,1))
);
CREATE TABLE yzc_study_dictation_setting (
 user_id TEXT NOT NULL PRIMARY KEY,
 book TEXT NOT NULL DEFAULT '',
 pause_each INTEGER NOT NULL DEFAULT 0 CHECK(pause_each IN (0,1)),
 random_order INTEGER NOT NULL DEFAULT 0 CHECK(random_order IN (0,1)),
 repeats INTEGER NOT NULL DEFAULT 1 CHECK(repeats BETWEEN 1 AND 5),
 interval INTEGER NOT NULL DEFAULT 1 CHECK(interval BETWEEN 1 AND 10)
);
CREATE TABLE yzc_study_jlpt_setting (
 user_id TEXT NOT NULL,
 entry_point TEXT NOT NULL CHECK(entry_point IN ('practice','test')),
 level TEXT NOT NULL DEFAULT 'N5' CHECK(level IN ('N1','N2','N3','N4','N5')),
 PRIMARY KEY(user_id,entry_point)
);
CREATE TABLE yzc_study_flashcard_setting (
 user_id TEXT NOT NULL PRIMARY KEY,
 book TEXT NOT NULL DEFAULT '',
 direction TEXT NOT NULL DEFAULT 'japanese' CHECK(direction IN ('japanese','chinese')),
 only_weak INTEGER NOT NULL DEFAULT 0 CHECK(only_weak IN (0,1)),
 random_order INTEGER NOT NULL DEFAULT 0 CHECK(random_order IN (0,1)),
 word_limit INTEGER NOT NULL DEFAULT 10 CHECK(word_limit IN (0,10,20))
);
CREATE TABLE yzc_study_flashcard_lesson (
 user_id TEXT NOT NULL,
 lessons_id TEXT NOT NULL,
 position INTEGER NOT NULL,
 PRIMARY KEY(user_id,lessons_id)
);
CREATE TABLE yzc_study_flashcard_session (
 user_id TEXT NOT NULL PRIMARY KEY,
 value TEXT NOT NULL
);
CREATE TABLE yzc_study_flashcard_mastery (
 user_id TEXT NOT NULL,
 word TEXT NOT NULL,
 direction TEXT NOT NULL,
 known INTEGER NOT NULL,
 time INTEGER NOT NULL,
 PRIMARY KEY(user_id,word,direction)
);
CREATE TABLE yzc_study_flashcard_answer (
 user_id TEXT NOT NULL,
 session TEXT NOT NULL,
 position INTEGER NOT NULL,
 word TEXT NOT NULL,
 known INTEGER NOT NULL,
 time INTEGER NOT NULL,
 PRIMARY KEY(user_id,session,position)
);
CREATE TABLE yzc_study_local_migration (
 name TEXT NOT NULL PRIMARY KEY,
 completed_at INTEGER NOT NULL
);

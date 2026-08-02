
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `counters` (
  `small_num` int UNSIGNED NOT NULL,
  `big_num` bigint UNSIGNED NOT NULL,
  `plain_int` int NOT NULL,
  `small_uns` smallint UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

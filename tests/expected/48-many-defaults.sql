
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `defaults_many` (
  `col_int` int NOT NULL DEFAULT 42,
  `col_str` varchar(255) NOT NULL DEFAULT 'hello',
  `col_zero` int NOT NULL DEFAULT 0,
  `col_one` int NOT NULL DEFAULT 1,
  `col_empty` varchar(255) NOT NULL DEFAULT 0,
  `col_big` bigint NOT NULL DEFAULT 999999999,
  `col_m` decimal(16, 2) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

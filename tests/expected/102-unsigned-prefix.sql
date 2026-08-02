
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `unsigned_test` (
  `plain_n` int NOT NULL,
  `plain_N` bigint NOT NULL,
  `plus_n` int UNSIGNED NOT NULL,
  `plus_N` bigint UNSIGNED NOT NULL,
  `plus_n_pk` int UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `plus_N_nn` bigint UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

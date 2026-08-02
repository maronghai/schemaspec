
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `user` (
  `name` varchar(32) NOT NULL,
  `email` varchar(128) NOT NULL,
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `create_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `update_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `version` bigint NOT NULL,
  `status` int NOT NULL DEFAULT 0,
  `deleted_at` datetime NOT NULL,
  `deleted_by` int NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `item` (
  `name` varchar(64) NOT NULL,
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `status` int NOT NULL DEFAULT 0,
  `version` bigint NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

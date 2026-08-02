
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `user` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `version` bigint NOT NULL,
  `status` int NOT NULL DEFAULT 0,
  `name` varchar(32) NOT NULL,
  `email` varchar(128) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

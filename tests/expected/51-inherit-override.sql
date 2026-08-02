
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `user` (
  `phone` varchar(16) NOT NULL,
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `email` varchar(128) NOT NULL,
  `name` varchar(64) NOT NULL,
  `version` bigint NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

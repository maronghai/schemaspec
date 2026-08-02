
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `user` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `email` varchar(128) NOT NULL,
  `name` varchar(32) NOT NULL,
  `code` varchar(16) NOT NULL,
  UNIQUE INDEX `uk_email` (`email`),
  UNIQUE INDEX `uk_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

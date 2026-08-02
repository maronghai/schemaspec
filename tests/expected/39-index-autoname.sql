
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `idx_test` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` varchar(32) NOT NULL,
  `email` varchar(128) NOT NULL,
  `content` text NOT NULL,
  UNIQUE INDEX `uk_email` (`email`),
  INDEX `idx_name` (`name`),
  FULLTEXT INDEX `ft_content` (`content`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

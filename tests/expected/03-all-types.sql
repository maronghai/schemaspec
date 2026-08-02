
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `all_types` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` varchar(255) NOT NULL,
  `full` text NOT NULL,
  `price` decimal(16, 2) NOT NULL,
  `big_p` decimal(20, 6) NOT NULL,
  `flag` boolean NOT NULL,
  `data` blob NOT NULL,
  `meta` json NOT NULL,
  `created` datetime NOT NULL,
  `born` date NOT NULL,
  `code` varchar(64) NOT NULL,
  `ver` bigint NOT NULL,
  `amt` decimal(10, 2) NOT NULL,
  `cnt` int NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

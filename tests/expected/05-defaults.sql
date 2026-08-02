
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `defaults` (
  `col1` int NOT NULL DEFAULT 0,
  `col2` varchar(255) NOT NULL DEFAULT 'hello',
  `col3` decimal(16, 2) NOT NULL DEFAULT 0,
  `col4` varchar(255) NOT NULL DEFAULT 0,
  `col5` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

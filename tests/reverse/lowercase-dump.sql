create table `orders` (
  `id` int not null auto_increment,
  `user_id` int not null,
  `total` decimal(10,2) not null default 0,
  `note` varchar(255) null,
  primary key (`id`),
  key `idx_orders_user` (`user_id`)
) engine=InnoDB default charset=utf8mb4;

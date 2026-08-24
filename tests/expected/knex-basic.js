/**
 * @param {import('knex').Knex} knex
 * @returns {Promise<void>}
 */
exports.up = function(knex) {
  // Test
  return knex.schema.createTable('Basic', function(table) {
  });

  return knex.schema.createTable('users', function(table) {
    table.increments('id').primary();
    table.string('name', 32).notNullable();
    table.string('email', 128).notNullable();
  });

  return knex.schema.createTable('orders', function(table) {
    table.increments('id').primary();
    table.integer('user_id').notNullable();
    table.decimal('amount', 16, 2).notNullable();
    table.foreign('user_id').references('users.id');
  });
};

/**
 * @param {import('knex').Knex} knex
 * @returns {Promise<void>}
 */
exports.down = function(knex) {
  return knex.schema.dropTableIfExists('orders');

  return knex.schema.dropTableIfExists('users');

  return knex.schema.dropTableIfExists('Basic');
};

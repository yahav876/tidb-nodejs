-- Create test database
CREATE DATABASE IF NOT EXISTS testdb;
USE testdb;

-- Create sample tables for testing CDC
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INT DEFAULT 0,
    category_id INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS categories (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status ENUM('pending', 'processing', 'shipped', 'delivered', 'cancelled') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS order_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(id),
    FOREIGN KEY (product_id) REFERENCES products(id)
);

-- Create default user
INSERT IGNORE INTO users (username, email, password_hash) VALUES
('admin', 'admin@example.com', '$2b$10$rQZ9v7B9Y8jJ7z1X0Q2Q2uXcZ9v7B9Y8jJ7z1X0Q2Q2uXcZ9v7B9Y8');

-- Insert sample categories
INSERT IGNORE INTO categories (name, description) VALUES
('Electronics', 'Electronic devices and gadgets'),
('Books', 'Books and publications'),
('Clothing', 'Apparel and accessories');

-- Insert sample products
INSERT IGNORE INTO products (name, description, price, stock_quantity, category_id) VALUES
('Laptop', 'High-performance laptop computer', 999.99, 10, 1),
('Smartphone', 'Latest model smartphone', 699.99, 25, 1),
('Programming Book', 'Learn programming fundamentals', 49.99, 50, 2),
('T-Shirt', 'Comfortable cotton t-shirt', 19.99, 100, 3);

-- Insert some test data to trigger CDC events
INSERT IGNORE INTO users (username, email, password_hash) VALUES
('testuser1', 'test1@example.com', 'hash1'),
('testuser2', 'test2@example.com', 'hash2');

INSERT IGNORE INTO categories (name, description) VALUES
('Software', 'Software and applications');

INSERT IGNORE INTO products (name, description, price, stock_quantity, category_id) VALUES
('IDE License', 'Professional IDE license', 299.99, 100, 4);

-- Create some test orders to trigger CDC events
INSERT IGNORE INTO orders (user_id, total_amount, status) VALUES
(1, 999.99, 'pending'),
(2, 49.99, 'processing');

INSERT IGNORE INTO order_items (order_id, product_id, quantity, price) VALUES
(1, 1, 1, 999.99),
(2, 3, 1, 49.99);

-- Show tables to confirm
SHOW TABLES;
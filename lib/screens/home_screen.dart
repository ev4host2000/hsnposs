import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Dashboard')), 
      body: GridView.count(
        padding: EdgeInsets.all(8.0),
        crossAxisCount: 2,
        children: <Widget>[
          _buildMenuCard('المصروفات', Icons.money, Colors.red),
          _buildMenuCard('الصندوق', Icons.account_balance, Colors.blue),
          _buildMenuCard('العملاء', Icons.person, Colors.green),
          _buildMenuCard('المبيعات', Icons.sell, Colors.orange),
          _buildMenuCard('الاستعلامات', Icons.question_answer, Colors.purple),
          _buildMenuCard('المخزن', Icons.store, Colors.brown),
          _buildMenuCard('الموردين', Icons.business, Colors.teal),
          _buildMenuCard('المشتريات', Icons.shopping_cart, Colors.yellow),
        ],
      ),
    );
  }

  Widget _buildMenuCard(String title, IconData icon, Color color) {
    return Card(
      color: color,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 50, color: Colors.white),
          SizedBox(height: 10),
          Text(title,
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
        ],
      ),
    );
  }
}
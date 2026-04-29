import 'package:get/get.dart';
import 'package:your_app/models/product_model.dart';

class ProductController extends GetxController {
  var products = <ProductModel>[].obs;

  void addProduct(ProductModel product) {
    products.add(product);
  }

  void removeProduct(ProductModel product) {
    products.remove(product);
  }

  void clearProducts() {
    products.clear();
  }

  List<ProductModel> get allProducts => products;
}
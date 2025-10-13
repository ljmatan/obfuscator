import 'utils.dart';
import 'api.dart';

@publicApi
class MyPublicClass {
  final String message;

  MyPublicClass(this.message);

  @publicApi
  void greet() {
    print('Greeting from public class: $message');
  }
}

class SecretClass {
  int _counter = 0;

  void increment() {
    _counter++;
    print('Counter is now $_counter');
  }
}

void main() {
  final pub = MyPublicClass('Hello');
  pub.greet();

  final sec = SecretClass();
  sec.increment();

  exampleGlobalHelperFunction();

  final util = ExampleUtility();

  util.doWork();
}

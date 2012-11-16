// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Additional Dart code may be 'placed on' hidden native classes.

import 'native_metadata.dart';

@Native("*A")
class A {

  var _field;

  int get X => _field;
  void set X(int x) { _field = x; }

  int method(int z) => _field + z;
}

@native A makeA() { return new A(); }

@Native("""
function A() {}
makeA = function(){return new A;};
""")
void setup();


main() {
  setup();

  var a = makeA();

  a.X = 100;
  Expect.equals(100, a.X);
  Expect.equals(150, a.method(50));
}

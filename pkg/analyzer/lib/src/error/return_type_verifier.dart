// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/element/type_provider.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/error_verifier.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:meta/meta.dart';

class ReturnTypeVerifier {
  final TypeProviderImpl _typeProvider;
  final TypeSystemImpl _typeSystem;
  final ErrorReporter _errorReporter;

  EnclosingExecutableContext enclosingExecutable;

  ReturnTypeVerifier({
    @required TypeProviderImpl typeProvider,
    @required TypeSystemImpl typeSystem,
    @required ErrorReporter errorReporter,
  })  : _typeProvider = typeProvider,
        _typeSystem = typeSystem,
        _errorReporter = errorReporter;

  DartType get _flattenedReturnType {
    var returnType = enclosingExecutable.returnType;
    if (enclosingExecutable.isSynchronous) {
      return returnType;
    } else {
      return _typeSystem.flatten(returnType);
    }
  }

  void verifyExpressionFunctionBody(ExpressionFunctionBody node) {
    // This enables concise declarations of void functions.
    if (_flattenedReturnType.isVoid) {
      return;
    }

    return _checkReturnExpression(node.expression);
  }

  void verifyReturnStatement(ReturnStatement statement) {
    var expression = statement.expression;

    if (enclosingExecutable.isGenerativeConstructor) {
      if (expression != null) {
        _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.RETURN_IN_GENERATIVE_CONSTRUCTOR,
          expression,
        );
      }
      return;
    }

    if (enclosingExecutable.isGenerator) {
      if (expression != null) {
        _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.RETURN_IN_GENERATOR,
          statement,
          [enclosingExecutable.isAsynchronous ? 'async*' : 'sync*'],
        );
      }
      return;
    }

    if (expression == null) {
      _checkReturnWithoutValue(statement);
      return;
    }

    _checkReturnExpression(expression);
  }

  void verifyReturnType(TypeAnnotation returnType) {
    // If no declared type, then the type is `dynamic`, which is valid.
    if (returnType == null) {
      return;
    }

    void checkElement(
      ClassElement expectedElement,
      StaticTypeWarningCode errorCode,
    ) {
      if (!_isLegalReturnType(expectedElement)) {
        enclosingExecutable.hasLegalReturnType = false;
        _errorReporter.reportErrorForNode(errorCode, returnType);
      }
    }

    if (enclosingExecutable.isAsynchronous) {
      if (enclosingExecutable.isGenerator) {
        checkElement(
          _typeProvider.streamElement,
          StaticTypeWarningCode.ILLEGAL_ASYNC_GENERATOR_RETURN_TYPE,
        );
      } else {
        checkElement(
          _typeProvider.futureElement,
          StaticTypeWarningCode.ILLEGAL_ASYNC_RETURN_TYPE,
        );
      }
    } else if (enclosingExecutable.isGenerator) {
      checkElement(
        _typeProvider.iterableElement,
        StaticTypeWarningCode.ILLEGAL_SYNC_GENERATOR_RETURN_TYPE,
      );
    }
  }

  /// Check that a type mismatch between the type of the [expression] and
  /// the expected return type of the enclosing executable.
  void _checkReturnExpression(Expression expression) {
    if (!enclosingExecutable.hasLegalReturnType) {
      // ILLEGAL_ASYNC_RETURN_TYPE has already been reported, meaning the
      // _declared_ return type is illegal; don't confuse by also reporting
      // that the type being returned here does not match that illegal return
      // type.
      return;
    }

    // `T` is the declared return type.
    // `S` is the static type of the expression.
    var T = enclosingExecutable.returnType;
    var S = getStaticType(expression);

    void reportTypeError() {
      String displayName = enclosingExecutable.element.displayName;
      if (displayName.isEmpty) {
        _errorReporter.reportErrorForNode(
          StaticTypeWarningCode.RETURN_OF_INVALID_TYPE_FROM_CLOSURE,
          expression,
          [S, T],
        );
      } else if (enclosingExecutable.isMethod) {
        _errorReporter.reportErrorForNode(
          StaticTypeWarningCode.RETURN_OF_INVALID_TYPE_FROM_METHOD,
          expression,
          [S, T, displayName],
        );
      } else {
        _errorReporter.reportErrorForNode(
          StaticTypeWarningCode.RETURN_OF_INVALID_TYPE_FROM_FUNCTION,
          expression,
          [S, T, displayName],
        );
      }
    }

    if (enclosingExecutable.isSynchronous) {
      // It is a compile-time error if `T` is `void`,
      // and `S` is neither `void`, `dynamic`, nor `Null`.
      if (T.isVoid) {
        if (!_isVoidDynamicOrNull(S)) {
          reportTypeError();
          return;
        }
      }
      // It is a compile-time error if `S` is `void`,
      // and `T` is neither `void`, `dynamic`, nor `Null`.
      if (S.isVoid) {
        if (!_isVoidDynamicOrNull(T)) {
          reportTypeError();
          return;
        }
      }
      // It is a compile-time error if `S` is not `void`,
      // and `S` is not assignable to `T`.
      if (!S.isVoid) {
        if (!_typeSystem.isAssignableTo2(S, T)) {
          reportTypeError();
          return;
        }
      }
      // OK
      return;
    }

    if (enclosingExecutable.isAsynchronous) {
      var flatten_T = _typeSystem.flatten(T);
      var flatten_S = _typeSystem.flatten(S);
      // It is a compile-time error if `T` is `void`,
      // and `flatten(S)` is neither `void`, `dynamic`, nor `Null`.
      if (T.isVoid) {
        if (!_isVoidDynamicOrNull(flatten_S)) {
          reportTypeError();
          return;
        }
      }
      // It is a compile-time error if `flatten(S)` is `void`,
      // and `flatten(T)` is neither `void`, `dynamic`, nor `Null`.
      if (flatten_S.isVoid) {
        if (!_isVoidDynamicOrNull(flatten_T)) {
          reportTypeError();
          return;
        }
      }
      // It is a compile-time error if `flatten(S)` is not `void`,
      // and `Future<flatten(S)>` is not assignable to `T`.
      if (!flatten_S.isVoid) {
        var future_flatten_S = _typeProvider.futureType2(flatten_S);
        if (!_typeSystem.isAssignableTo2(future_flatten_S, T)) {
          reportTypeError();
          return;
        }
        // OK
        return;
      }
    }
  }

  void _checkReturnWithoutValue(ReturnStatement statement) {
    var returnType = _flattenedReturnType;
    if (_isVoidDynamicOrNull(returnType)) {
      return;
    }

    _errorReporter.reportErrorForToken(
      StaticWarningCode.RETURN_WITHOUT_VALUE,
      statement.returnKeyword,
    );
  }

  bool _isLegalReturnType(ClassElement expectedElement) {
    DartType returnType = enclosingExecutable.returnType;
    //
    // When checking an async/sync*/async* method, we know the exact type
    // that will be returned (e.g. Future, Iterable, or Stream).
    //
    // For example an `async` function body will return a `Future<T>` for
    // some `T` (possibly `dynamic`).
    //
    // We allow the declared return type to be a supertype of that
    // (e.g. `dynamic`, `Object`), or Future<S> for some S.
    // (We assume the T <: S relation is checked elsewhere.)
    //
    // We do not allow user-defined subtypes of Future, because an `async`
    // method will never return those.
    //
    // To check for this, we ensure that `Future<bottom> <: returnType`.
    //
    // Similar logic applies for sync* and async*.
    //
    var lowerBound = expectedElement.instantiate(
      typeArguments: [NeverTypeImpl.instance],
      nullabilitySuffix: NullabilitySuffix.star,
    );
    return _typeSystem.isSubtypeOf2(lowerBound, returnType);
  }

  /// Return the static type of the given [expression] that is to be used for
  /// type analysis.
  ///
  /// TODO(scheglov) this is duplicate
  static DartType getStaticType(Expression expression) {
    DartType type = expression.staticType;
    if (type == null) {
      // TODO(brianwilkerson) This should never happen.
      return DynamicTypeImpl.instance;
    }
    return type;
  }

  static bool _isVoidDynamicOrNull(DartType type) {
    return type.isVoid || type.isDynamic || type.isDartCoreNull;
  }
}
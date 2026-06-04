// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:dio/dio.dart' as _i361;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:zdrive_app/core/auth/token_storage.dart' as _i323;
import 'package:zdrive_app/core/network/auth_interceptor.dart' as _i248;
import 'package:zdrive_app/core/network/dio_client.dart' as _i904;
import 'package:zdrive_app/core/storage/app_preferences.dart' as _i736;
import 'package:zdrive_app/features/auth/data/auth_remote_data_source.dart'
    as _i568;
import 'package:zdrive_app/features/auth/data/auth_repository_impl.dart'
    as _i432;
import 'package:zdrive_app/features/auth/domain/auth_repository.dart' as _i97;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  Future<_i174.GetIt> init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final networkModule = _$NetworkModule();
    gh.lazySingleton<_i323.TokenStorage>(() => _i323.TokenStorage());
    await gh.lazySingletonAsync<_i736.AppPreferences>(() {
      final i = _i736.AppPreferences();
      return i.init().then((_) => i);
    }, preResolve: true);
    gh.lazySingleton<_i248.AuthInterceptor>(
      () => _i248.AuthInterceptor(gh<_i323.TokenStorage>()),
    );
    gh.lazySingleton<_i361.Dio>(
      () => networkModule.dio(gh<_i248.AuthInterceptor>()),
    );
    gh.lazySingleton<_i568.AuthRemoteDataSource>(
      () => _i568.AuthRemoteDataSource(gh<_i361.Dio>()),
    );
    gh.lazySingleton<_i97.AuthRepository>(
      () => _i432.AuthRepositoryImpl(
        gh<_i568.AuthRemoteDataSource>(),
        gh<_i323.TokenStorage>(),
      ),
    );
    return this;
  }
}

class _$NetworkModule extends _i904.NetworkModule {}

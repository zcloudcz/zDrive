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
import 'package:zdrive_app/features/files/data/file_remote_data_source.dart'
    as _i466;
import 'package:zdrive_app/features/files/data/file_repository_impl.dart'
    as _i884;
import 'package:zdrive_app/features/files/data/file_upload_data_source.dart'
    as _i223;
import 'package:zdrive_app/features/files/domain/file_repository.dart'
    as _i1043;
import 'package:zdrive_app/features/files/domain/use_cases/create_folder_use_case.dart'
    as _i247;
import 'package:zdrive_app/features/files/domain/use_cases/delete_file_use_case.dart'
    as _i931;
import 'package:zdrive_app/features/files/domain/use_cases/list_files_use_case.dart'
    as _i955;
import 'package:zdrive_app/features/files/domain/use_cases/search_files_use_case.dart'
    as _i1021;
import 'package:zdrive_app/features/files/domain/use_cases/share_file_use_case.dart'
    as _i694;
import 'package:zdrive_app/features/files/domain/use_cases/upload_file_use_case.dart'
    as _i622;

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
    gh.lazySingleton<_i466.FileRemoteDataSource>(
      () => _i466.FileRemoteDataSource(gh<_i361.Dio>()),
    );
    gh.lazySingleton<_i223.FileUploadDataSource>(
      () => _i223.FileUploadDataSource(gh<_i361.Dio>()),
    );
    gh.lazySingleton<_i1043.FileRepository>(
      () => _i884.FileRepositoryImpl(
        gh<_i466.FileRemoteDataSource>(),
        gh<_i223.FileUploadDataSource>(),
      ),
    );
    gh.lazySingleton<_i247.CreateFolderUseCase>(
      () => _i247.CreateFolderUseCase(gh<_i1043.FileRepository>()),
    );
    gh.lazySingleton<_i931.DeleteFileUseCase>(
      () => _i931.DeleteFileUseCase(gh<_i1043.FileRepository>()),
    );
    gh.lazySingleton<_i955.ListFilesUseCase>(
      () => _i955.ListFilesUseCase(gh<_i1043.FileRepository>()),
    );
    gh.lazySingleton<_i1021.SearchFilesUseCase>(
      () => _i1021.SearchFilesUseCase(gh<_i1043.FileRepository>()),
    );
    gh.lazySingleton<_i694.ShareFileUseCase>(
      () => _i694.ShareFileUseCase(gh<_i1043.FileRepository>()),
    );
    gh.lazySingleton<_i622.UploadFileUseCase>(
      () => _i622.UploadFileUseCase(gh<_i1043.FileRepository>()),
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

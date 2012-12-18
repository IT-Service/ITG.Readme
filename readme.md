﻿ITG.Readme
==========

Набор функций для PowerShell для генерации readme файла для модулей и функций.

Версия модуля: **1.3.7**

Функции модуля
--------------
			
### Readme
			
#### Get-Readme

Генерирует readme файл с md разметкой по данным модуля и комментариям к его функциям.
Файл предназначен, в частности, для размещения в репозиториях github.
	
	Get-Readme [-ModuleInfo] <PSModuleInfo> [-OutDefaultFile] [-ShortDescription] <CommonParameters>
	
	Get-Readme [-ExternalScriptInfo] <ExternalScriptInfo> [-ShortDescription] <CommonParameters>
	
	Get-Readme [-FunctionInfo] <FunctionInfo> [-ShortDescription] <CommonParameters>

Подробное описание функций модуля
---------------------------------
			
#### Get-Readme

Генерирует readme файл с md разметкой по данным модуля и комментариям к его функциям.
Файл предназначен, в частности, для размещения в репозиториях github.

##### Синтаксис
	
	Get-Readme [-ModuleInfo] <PSModuleInfo> [-OutDefaultFile] [-ShortDescription] <CommonParameters>
	
	Get-Readme [-ExternalScriptInfo] <ExternalScriptInfo> [-ShortDescription] <CommonParameters>
	
	Get-Readme [-FunctionInfo] <FunctionInfo> [-ShortDescription] <CommonParameters>

##### Параметры	

- `ModuleInfo <PSModuleInfo>
        Описатель модуля
        
        Требуется?                    true
        Позиция?                    1
        Значение по умолчанию                
        Принимать входные данные конвейера?true (ByValue)
        Принимать подстановочные знаки?
        
- `OutDefaultFile [<SwitchParameter>]
        
        Требуется?                    false
        Позиция?                    named
        Значение по умолчанию                
        Принимать входные данные конвейера?false
        Принимать подстановочные знаки?
        
- `ExternalScriptInfo <ExternalScriptInfo>
        Описатель внешнего сценария
        
        Требуется?                    true
        Позиция?                    1
        Значение по умолчанию                
        Принимать входные данные конвейера?true (ByValue)
        Принимать подстановочные знаки?
        
- `FunctionInfo <FunctionInfo>
        Описатель внешнего сценария
        
        Требуется?                    true
        Позиция?                    1
        Значение по умолчанию                
        Принимать входные данные конвейера?true (ByValue)
        Принимать подстановочные знаки?
        
- `ShortDescription [<SwitchParameter>]
        
        Требуется?                    false
        Позиция?                    named
        Значение по умолчанию                
        Принимать входные данные конвейера?false
        Принимать подстановочные знаки?
        
- `<CommonParameters>
        Данный командлет поддерживает общие параметры: Verbose, Debug,
        ErrorAction, ErrorVariable, WarningAction, WarningVariable,
        OutBuffer и OutVariable. Для получения дополнительных сведений введите
        "get-help about_commonparameters".





##### Примеры использования	

1. Генерация readme.md файла для модуля `ITG.Yandex.DnsServer` 
в текущем каталоге.

		Get-Module 'ITG.Yandex.DnsServer' | Get-Readme | Out-File -Path 'readme.md' -Encoding 'UTF8' -Width 1024;

2. Генерация readme.md файла для модуля `ITG.Yandex.DnsServer` 
в каталоге модуля.

		Get-Module 'ITG.Yandex.DnsServer' | Get-Readme -OutDefaultFile;

##### Связанные ссылки

- [MarkDown (md) Syntax](http://daringfireball.net/projects/markdown/syntax)
- [about_comment_based_help](http://technet.microsoft.com/ru-ru/library/dd819489.aspx)
- [Написание справки для командлетов](http://go.microsoft.com/fwlink/?LinkID=123415)
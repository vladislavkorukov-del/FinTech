#!/usr/bin/env python3
"""Build/verify the offline Russian bank catalog and its original logos.

Source of truth for the list of credit organizations is the official Bank of
Russia BIC directory (ED807, https://www.cbr.ru/s/newbik). Only participants
with PtType=20 (credit organizations) are included; branches, treasury and
Bank of Russia divisions are not banks a person keeps an account in.

Modes (network is developer-only and opt-in):
  --build ED807.zip   regenerate assets/banks/registry.json and
                      lib/domain/bank_catalog.dart from a downloaded directory
  --fetch-logos       download the curated original logos (Wikimedia Commons)
                      into assets/banks/ and write assets/banks/manifest.json
  --render            render PNG display copies (Inkscape for SVG originals)
  --verify            offline: registry/Dart/logos/PNGs agree with recorded SHA

A logo is attached only when an original file of the bank's *current* mark is
available with recorded provenance. Every other organization is shown with a
neutral, unbranded bank glyph; no logo is drawn or guessed.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets/banks'
RASTER = ASSETS / 'raster'
REGISTRY = ASSETS / 'registry.json'
MANIFEST = ASSETS / 'manifest.json'
RASTER_MANIFEST = RASTER / 'manifest.json'
DART = ROOT / 'lib/domain/bank_catalog.dart'
SOURCE_URL = 'https://www.cbr.ru/s/newbik'
SIZE = 384
GUTTER = 2
MAX_BYTES = 2 * 1024 * 1024
UA = {'User-Agent': 'Finance-bank-catalog/1.6 (https://github.com/vladislavkorukov-del/FinTech)'}
# Some bank sites refuse non-browser clients; their public icons are fetched
# with an ordinary mobile browser identification.
BROWSER_UA = {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36'}

# Brand names people actually use, plus former names/abbreviations for search.
# Keys are Bank of Russia registration numbers; names are verified against the
# official directory at build time (a missing number fails the build).
BRANDS = {
    '1481': ('Сбербанк', ['Сбер', 'Сбербанк России', 'Sber', 'Sberbank']),
    '1000': ('ВТБ', ['Банк ВТБ', 'ВТБ24', 'VTB']),
    '354': ('Газпромбанк', ['ГПБ', 'Банк ГПБ', 'Gazprombank']),
    '1326': ('Альфа-Банк', ['Альфа', 'Альфабанк', 'Alfa-Bank', 'Alfa Bank']),
    '2673': ('Т-Банк', ['ТБанк', 'Т Банк', 'Тинькофф', 'Тинькофф Банк', 'T-Bank', 'Tinkoff']),
    '3349': ('Россельхозбанк', ['РСХБ', 'Rosselkhozbank']),
    '963': ('Совкомбанк', ['Халва', 'Sovcombank']),
    '3292': ('Райффайзенбанк', ['Райффайзен', 'Raiffeisen', 'Raiffeisenbank']),
    '3251': ('ПСБ', ['Промсвязьбанк', 'Банк ПСБ', 'PSB', 'Promsvyazbank']),
    '1978': ('МКБ', ['Московский кредитный банк', 'MKB', 'Credit Bank of Moscow']),
    '2312': ('Банк ДОМ.РФ', ['ДОМ.РФ', 'Дом РФ', 'DOM.RF']),
    '2766': ('ОТП Банк', ['ОТП', 'OTP Bank', 'OTP']),
    '3545': ('Точка', ['Банк Точка', 'Tochka']),
    '3027': ('Яндекс Банк', ['Yandex Bank', 'Яндекс Пэй', 'Yandex Pay']),
    '3542': ('Озон Банк', ['Ozon Банк', 'Ozon Bank', 'Озон']),
    '841': ('WB Банк', ['ВБ Банк', 'Вайлдберриз Банк', 'Wildberries Банк', 'WB Bank']),
    '2306': ('Абсолют Банк', ['Абсолют', 'Absolut Bank']),
    '1810': ('АТБ', ['Азиатско-Тихоокеанский Банк', 'ATB']),
    '2590': ('Ак Барс Банк', ['Ак Барс', 'Ak Bars']),
    '328': ('Банк «Россия»', ['АБ Россия', 'Банк Россия', 'Bank Rossiya']),
    '2268': ('МТС Банк', ['МТС-Банк', 'MTS Bank']),
    '2557': ('РенКап Банк', ['Ситибанк', 'Citibank', 'RenCap Bank']),
    '316': ('Хоум Банк', ['ХКФ Банк', 'Хоум Кредит', 'Home Credit', 'Home Bank']),
    '3354': ('Ренессанс Банк', ['Ренессанс Кредит', 'Renaissance Credit']),
    '3255': ('Банк Зенит', ['Зенит', 'Zenit']),
    '1927': ('Модульбанк', ['Модуль', 'Modulbank']),
    '2225': ('Центр-инвест', ['Центр инвест', 'Center-invest']),
    '429': ('УБРиР', ['Уральский банк реконструкции и развития', 'UBRR']),
    '3510-К': ('ЮMoney', ['Юмани', 'YooMoney', 'Яндекс Деньги', 'ЮMoney НКО']),
    '2275': ('Уралсиб', ['Банк Уралсиб', 'Uralsib']),
    '436': ('Банк «Санкт-Петербург»', ['БСПБ', 'Банк Санкт-Петербург', 'Bank Saint Petersburg']),
    '2289': ('Русский Стандарт', ['Банк Русский Стандарт', 'Russian Standard']),
    '1': ('ЮниКредит Банк', ['ЮниКредит', 'UniCredit']),
    '2998': ('Экспобанк', ['Expobank']),
    '2707': ('Локо-Банк', ['Локо', 'Loko-Bank']),
    '101': ('БКС Банк', ['БКС', 'BCS Bank']),
    '2799': ('Банк Финам', ['Финам', 'Finam']),
    '2546': ('Новикомбанк', ['Novikombank']),
    '705': ('Банк Синара', ['Синара', 'СКБ-Банк', 'Sinara']),
    '3223': ('Свой Банк', ['Свой', 'Svoi Bank']),
    '2879': ('Банк Авангард', ['Авангард', 'Avangard']),
    '3311': ('Кредит Европа Банк', ['Credit Europe Bank']),
    '2440': ('Металлинвестбанк', ['Metallinvestbank']),
    '3279': ('Банк Траст', ['Траст', 'Trust']),
    '1143': ('Цифра банк', ['Цифра', 'Cifra bank']),
    '2368': ('Бланк банк', ['Бланк', 'Blanc bank']),
    '3538': ('Банк 131', ['131', 'Bank 131']),
    '1751': ('Мособлбанк', ['Mosoblbank']),
    '2733': ('Примсоцбанк', ['Primsotsbank']),
    '2210': ('ТКБ Банк', ['ТКБ', 'TKB Bank']),
}

# Original files of the current marks, chosen per bank after visual review.
# Each records its source (the bank's own website, or Wikimedia Commons with
# license metadata) and SHA-256; files are kept byte-for-byte unchanged.
# Commons candidates were rate-limited (HTTP 429) for this build host; banks
# whose official sites fail TLS verification are not fetched (no TLS bypass).
LOGOS = {
    '354': {'sourceType': 'official-website', 'url': 'https://www.gazprombank.ru/_next/d55dda96b60568876d54429fe31cd2e1/_next/public/favicons/default/dark-favicon/favicon-32x32.svg', 'page': 'https://www.gazprombank.ru/',
            'sha256': '9362f737d73b3fdb47736cda818d6155ec798db997b5256c91bcbca33e2a1943', 'why': 'Official site icon of Gazprombank (current blue sphere mark).'},
    '3292': {'sourceType': 'official-website', 'url': 'https://www.raiffeisen.ru/fav/icon.svg', 'page': 'https://www.raiffeisen.ru/',
            'sha256': 'd10befdbba057b662cb7f004d9e8d38c6c839abc1d9430e72a6179f29f1b4c27', 'why': 'Official site icon of Raiffeisenbank (yellow/black gable mark).'},
    '1': {'sourceType': 'official-website', 'url': 'https://www.unicreditbank.ru/etc/designs/cee2020-pws-ru/img/logos/apple-touch-icon.png', 'page': 'https://www.unicreditbank.ru/',
            'sha256': '83268539d5125a07613cae8262c0a54db31f8d28761bc2ca5d7939f00786c122', 'why': 'Official apple-touch-icon of UniCredit Bank Russia (red disc mark).'},
    '3510-К': {'sourceType': 'official-website', 'url': 'https://static.yoomoney.ru/files-front/resources/head/wallet/apple-touch-icon.png', 'page': 'https://yoomoney.ru/',
            'sha256': '728487cc0ec5bd61d0890f18f9fe50ca7d8223bf8e4ee24705d4b715de839754', 'why': 'Official apple-touch-icon of YooMoney (violet «ЮO» mark).'},
    '3542': {'sourceType': 'official-website', 'url': 'https://finance.ozon.ru/apple-touch-icon.png', 'page': 'https://finance.ozon.ru/',
            'sha256': '26b686c65be73ba97d6b615a9511a773c254025f8195b93f8a1c9fd6a4408235', 'why': 'Official apple-touch-icon of Ozon Bank (finance.ozon.ru).'},
    '1810': {'sourceType': 'official-website', 'url': 'https://www.atb.su/favicon.svg', 'page': 'https://www.atb.su/',
            'sha256': 'adb3ecab889ea17c88b9c4de23390be1a89815b7ea50cc0950967de370f093f2', 'why': 'Official site icon of Asian-Pacific Bank (ATB).'},
    '2225': {'sourceType': 'official-website', 'url': 'https://www.centrinvest.ru/favicon.svg', 'page': 'https://www.centrinvest.ru/',
            'sha256': '9f65216470f595a8d18ea02cb8403c7b57223c361626ec1ba611f927bcb1b969', 'why': 'Official site icon of Center-invest bank.'},
    '2799': {'sourceType': 'official-website', 'url': 'https://cdn-lpbr01.finam.ru/lpbr-static/favicon_e58c47cd78.svg', 'page': 'https://www.finambank.ru/',
            'sha256': '1a52a2aaf178ce7fa5ea44255d9b8222295891fe42c7c1ab3451385feb581405', 'why': 'Icon served by the official Bank Finam site (finambank.ru → finam.ru); Finam group mark, parent brand.'},
    '3223': {'sourceType': 'official-website', 'url': 'https://svoi.ru/icons/icon-512x512.png?v=53d8383916a19f9ee0e71ff783b1a8e3', 'page': 'https://svoi.ru/',
            'sha256': '95eaa55ae553ae240713b15dcc8377f85e2b910a8bbcaf5860827f3634a91e5f', 'why': 'Official apple-touch-icon of Svoi Bank.'},
    '3311': {'sourceType': 'official-website', 'url': 'https://www.crediteurope.ru/bitrix/templates/custom/favicon.svg', 'page': 'https://www.crediteurope.ru/',
            'sha256': 'b791536f8df8f799e0425117bb7fb903a8beea54fa45662c1fab9749ffb4bbae', 'why': 'Official site icon of Credit Europe Bank (Russia).'},
    '3538': {'sourceType': 'official-website', 'url': 'https://131.ru/favicon.svg', 'page': 'https://131.ru/',
            'sha256': 'e175cabd0c555785df84b311a5a45d9478d42eeefb0711d8ba8f76cb8db908a6', 'why': 'Official site icon of Bank 131.'},
    # 1.12: site icons through public favicon mirrors (the sites themselves fail
    # TLS verification from the build host). Reviewed by eye; refused: Хоум Банк
    # (site now serves the Sovcombank mark), Цифра банк (old «F» of the former
    # brand), РенКап, Зенит, Авангард, Мособлбанк, Примсоцбанк (only blurry
    # small favicons).
    '1481': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Fsberbank.ru&size=256", 'page': 'https://sberbank.ru/',
            'sha256': 'dad980542683010a0d0faa83bc936ca1bbdbb475d67949c556033e79522fdd17', 'why': 'Site icon of https://sberbank.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '1000': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Fvtb.ru&size=256", 'page': 'https://vtb.ru/',
            'sha256': '950c934651a0ccb94020b1bcbb3e6629d79170e07a1a392bf8ba9beec270ff35', 'why': 'Site icon of https://vtb.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '1326': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Falfabank.ru&size=256", 'page': 'https://alfabank.ru/',
            'sha256': '57d914ddee89f30c0587a7a66611f83d33861defcc149427e7c61ce87717358a', 'why': 'Site icon of https://alfabank.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '2673': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Ftbank.ru&size=256", 'page': 'https://tbank.ru/',
            'sha256': 'f9a33200e9e5fd804635ff99b649cb91e0dda142c54df765cd0dec5d0d04f1dc', 'why': 'Site icon of https://tbank.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '3349': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Frshb.ru&size=256", 'page': 'https://rshb.ru/',
            'sha256': 'ee7739c68ef9b0d361e4915207fa26a7dedfb01bc2374e1aa2dc2421da9fbb33', 'why': 'Site icon of https://rshb.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '963': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Fsovcombank.ru&size=256", 'page': 'https://sovcombank.ru/',
            'sha256': 'e96dac369d4992d0ccb59208808253612248e56f30fe234072df80cfd31bb890', 'why': 'Site icon of https://sovcombank.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '3251': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Fpsbank.ru&size=256", 'page': 'https://psbank.ru/',
            'sha256': '56c21ab514862f951594222fc55343960abc80561b212277278b685faf571f89', 'why': 'Site icon of https://psbank.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '1978': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Fmkb.ru&size=256", 'page': 'https://mkb.ru/',
            'sha256': 'f6612c2e8ecc3fb8ed11d80a9b76d05dfe22f097f3042a1ce81f0d622a9e9333', 'why': 'Site icon of https://mkb.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '2312': {'sourceType': 'yandex-favicon-service', 'url': "https://favicon.yandex.net/favicon/v2/domrfbank.ru?size=120&stub=0", 'page': 'https://domrfbank.ru/',
            'sha256': '8b915b344d5c857b99b7398684041e7f04dd61576c1a7fdc74fdca0c393494cb', 'why': 'Site icon of https://domrfbank.ru/ as served by the Yandex favicon service; reviewed as the current mark.'},
    '2766': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Fotpbank.ru&size=256", 'page': 'https://otpbank.ru/',
            'sha256': 'c384013e0fc0cb4849dd9c0b02e758639363d5ab8cc765d6293276f4295df505', 'why': 'Site icon of https://otpbank.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '3545': {'sourceType': 'yandex-favicon-service', 'url': "https://favicon.yandex.net/favicon/v2/tochka.com?size=120&stub=0", 'page': 'https://tochka.com/',
            'sha256': '55977ed7fda6fd81ef6295848d58608623ef24e93058053be0a86b96aa330d60', 'why': 'Site icon of https://tochka.com/ as served by the Yandex favicon service; reviewed as the current mark.'},
    '3027': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Fbank.yandex.ru&size=256", 'page': 'https://bank.yandex.ru/',
            'sha256': 'b53c2fe635697878aa5c22271f2c539612cd009b33023eec6e6c7bafb51243bb', 'why': 'Site icon of https://bank.yandex.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '841': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Fwb-bank.ru&size=256", 'page': 'https://wb-bank.ru/',
            'sha256': '3639bfcf45125ae39e25c6de9b329415cc685975e4ce0d6208342d7c4b426c3b', 'why': 'Site icon of https://wb-bank.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '2306': {'sourceType': 'yandex-favicon-service', 'url': "https://favicon.yandex.net/favicon/v2/absolutbank.ru?size=120&stub=0", 'page': 'https://absolutbank.ru/',
            'sha256': 'ef1349074ad25cbd4314950c3bf2c96e2cada50d265f1b10265efe923b40959a', 'why': 'Site icon of https://absolutbank.ru/ as served by the Yandex favicon service; reviewed as the current mark.'},
    '2590': {'sourceType': 'yandex-favicon-service', 'url': "https://favicon.yandex.net/favicon/v2/akbars.ru?size=120&stub=0", 'page': 'https://akbars.ru/',
            'sha256': '25dc4a0067f7c6d1b9f533b7a388979b4ae75ffe6dae1e4b854758d4f144cf54', 'why': 'Site icon of https://akbars.ru/ as served by the Yandex favicon service; reviewed as the current mark.'},
    '328': {'sourceType': 'yandex-favicon-service', 'url': "https://favicon.yandex.net/favicon/v2/abr.ru?size=120&stub=0", 'page': 'https://abr.ru/',
            'sha256': '329c23d5eb5d92a02a94e2d0575dd400ec80a19da1d08aaa1c9c13c108f1d13f', 'why': 'Site icon of https://abr.ru/ as served by the Yandex favicon service; reviewed as the current mark.'},
    '2268': {'sourceType': 'yandex-favicon-service', 'url': "https://favicon.yandex.net/favicon/v2/mtsbank.ru?size=120&stub=0", 'page': 'https://mtsbank.ru/',
            'sha256': 'ac861809f766bec5a77009906c7838d9b7eeb87209b96a0b917591b005a202ca', 'why': 'Site icon of https://mtsbank.ru/ as served by the Yandex favicon service; reviewed as the current mark.'},
    '3354': {'sourceType': 'yandex-favicon-service', 'url': "https://favicon.yandex.net/favicon/v2/rencredit.ru?size=120&stub=0", 'page': 'https://rencredit.ru/',
            'sha256': '0a35c991aefc120148aee2c94ea7681be795af7be525c7e349534c305a5d813f', 'why': 'Site icon of https://rencredit.ru/ as served by the Yandex favicon service; reviewed as the current mark.'},
    '1927': {'sourceType': 'yandex-favicon-service', 'url': "https://favicon.yandex.net/favicon/v2/modulbank.ru?size=120&stub=0", 'page': 'https://modulbank.ru/',
            'sha256': '2c34d731fab2cb44786ba8011710d82fa749a1ea3664d844d4edee7f7f6110e2', 'why': 'Site icon of https://modulbank.ru/ as served by the Yandex favicon service; reviewed as the current mark.'},
    '429': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Fubrr.ru&size=256", 'page': 'https://ubrr.ru/',
            'sha256': '597571e3bceafce82f0cd49227ea72edd66929220dff530797628d52f75d7629', 'why': 'Site icon of https://ubrr.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '2275': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Furalsib.ru&size=256", 'page': 'https://uralsib.ru/',
            'sha256': '95497a6f5fb40f8382c8066fef12b980189cf64bfb79f97dd8da16f7429e63b7', 'why': 'Site icon of https://uralsib.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '436': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Fbspb.ru&size=256", 'page': 'https://bspb.ru/',
            'sha256': '8a15b4a4ab2e864963c173225fd8994fb5824345e645dc79ad4668ef643099c7', 'why': 'Site icon of https://bspb.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '2289': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Frsb.ru&size=256", 'page': 'https://rsb.ru/',
            'sha256': 'd9280a9d3223dcae533650ac525bfda5b33a6cef02f416955bd695b8fb446796', 'why': 'Site icon of https://rsb.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '2998': {'sourceType': 'yandex-favicon-service', 'url': "https://favicon.yandex.net/favicon/v2/expobank.ru?size=120&stub=0", 'page': 'https://expobank.ru/',
            'sha256': 'fbfaaf5afe66974d7603b884b85936e966882e0f5b823ac7c3c38511b3e4c353', 'why': 'Site icon of https://expobank.ru/ as served by the Yandex favicon service; reviewed as the current mark.'},
    '2707': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Flockobank.ru&size=256", 'page': 'https://lockobank.ru/',
            'sha256': '089566394aff28d707477214f906ce310ce6e6fe9d2a468b47a43b37a98f4f7c', 'why': 'Site icon of https://lockobank.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '101': {'sourceType': 'yandex-favicon-service', 'url': "https://favicon.yandex.net/favicon/v2/bcs-bank.com?size=120&stub=0", 'page': 'https://bcs-bank.com/',
            'sha256': '6700a700c8c8460174ada46916f129eee8e530c1d98ec9b9964d34210d6d29a8', 'why': 'Site icon of https://bcs-bank.com/ as served by the Yandex favicon service; reviewed as the current mark.'},
    '2546': {'sourceType': 'yandex-favicon-service', 'url': "https://favicon.yandex.net/favicon/v2/novikom.ru?size=120&stub=0", 'page': 'https://novikom.ru/',
            'sha256': 'cf714a0d2dfae89c9e4be5c104ab32a9f42bdf2100d88700cf4a6fc3e1634a7a', 'why': 'Site icon of https://novikom.ru/ as served by the Yandex favicon service; reviewed as the current mark.'},
    '705': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Fsinara.ru&size=256", 'page': 'https://sinara.ru/',
            'sha256': '41e51a33665c362fb66d96fabbe820821c11812a32585a2d5ef73a9716704859', 'why': 'Site icon of https://sinara.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '2440': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Fmetallinvestbank.ru&size=256", 'page': 'https://metallinvestbank.ru/',
            'sha256': 'ac2ea8d0ef74f922f1cb89f418455ebe3eb9debc4649d0f728b32336799b25d3', 'why': 'Site icon of https://metallinvestbank.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '3279': {'sourceType': 'yandex-favicon-service', 'url': "https://favicon.yandex.net/favicon/v2/trust.ru?size=120&stub=0", 'page': 'https://trust.ru/',
            'sha256': '8af57e7bb247190a98c4a9c6775ce601c73efd4bef9094e0a7318a1c04269c02', 'why': 'Site icon of https://trust.ru/ as served by the Yandex favicon service; reviewed as the current mark.'},
    '2368': {'sourceType': 'google-favicon-service', 'url': "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https%3A%2F%2Fblanc.ru&size=256", 'page': 'https://blanc.ru/',
            'sha256': '448a387ea751aa943c16ebdd8059fab3e4b406406e847bab4c320e6a1a8afa2a', 'why': 'Site icon of https://blanc.ru/ as served by the Google favicon service; reviewed as the current mark.'},
    '2210': {'sourceType': 'yandex-favicon-service', 'url': "https://favicon.yandex.net/favicon/v2/tkbbank.ru?size=120&stub=0", 'page': 'https://tkbbank.ru/',
            'sha256': '85649f3e1bff72216b568f6cf779d4d3498fe130f4e6c23892a24ec28541d7d5', 'why': 'Site icon of https://tkbbank.ru/ as served by the Yandex favicon service; reviewed as the current mark.'},
}


HELPERS = r"""
  static final Map<String, RussianBank> _byReg = {
    for (final bank in entries) bank.regNumber.toUpperCase(): bank,
  };
  static final Map<String, RussianBank> _byBic = {
    for (final bank in entries)
      for (final bic in bank.bics) bic: bank,
  };

  static final Map<String, RussianBank> _byId = {
    for (final bank in entries) bank.id: bank,
  };
  static RussianBank? byId(String? id) => _byId[id];

  static RussianBank? byRegNumber(String? value) =>
      value == null ? null : _byReg[value.trim().toUpperCase()];
  static RussianBank? byBic(String? value) =>
      value == null ? null : _byBic[value.trim()];

  static String _key(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[«»"“”„()\-–—.,/]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Exact name, brand, former name, registration number or BIC. Ambiguous
  /// text returns null instead of guessing an institution.
  static RussianBank? byName(String? value) {
    if (value == null || _key(value).isEmpty) return null;
    final wanted = _key(value);
    final direct = byRegNumber(value) ?? byBic(value);
    if (direct != null) return direct;
    final found = entries
        .where(
          (bank) =>
              _key(bank.name) == wanted ||
              _key(bank.officialName) == wanted ||
              bank.aliases.any((alias) => _key(alias) == wanted),
        )
        .toList();
    return found.length == 1 ? found.single : null;
  }

  /// All query words must occur; exact names rank first, then names that
  /// start with the query, then word-prefix and plain substring matches.
  static List<RussianBank> search(String query) {
    final wanted = _key(query);
    final terms = wanted.split(' ').where((s) => s.isNotEmpty).toList();
    if (terms.isEmpty) return entries;
    final ranked = <(int, int, RussianBank)>[];
    for (var i = 0; i < entries.length; i++) {
      final bank = entries[i];
      final names = [bank.name, bank.officialName, ...bank.aliases].map(_key);
      final haystack = _key(
        [
          bank.name,
          bank.officialName,
          bank.regNumber,
          bank.city,
          ...bank.bics,
          ...bank.aliases,
        ].join(' '),
      );
      if (!terms.every(haystack.contains)) continue;
      final words = haystack.split(' ');
      final rank = names.any((n) => n == wanted) || bank.bics.contains(wanted)
          ? 0
          : names.any((n) => n.startsWith(wanted))
          ? 1
          : terms.every((t) => words.any((w) => w.startsWith(t)))
          ? 2
          : 3;
      ranked.add((rank, i, bank));
    }
    ranked.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    return [for (final item in ranked) item.$3];
  }"""


def digest(data):
    return hashlib.sha256(data).hexdigest()


def id_for(reg):
    return 'bank_' + re.sub(r'[^0-9a-z]', '', reg.lower().replace('к', 'k').replace('ц', 'c'))


LEGAL = r'(?:ПАО|ОАО|ЗАО|АО|ООО|НКО|РНКО|КБ|АКБ|АИКБ|КИБ|ИКБР|МКИБ|ЦК|СКБ|НБКО)'


def clean_name(official):
    name = official.replace('&quot;', '"')
    name = re.sub(r'\((?:ПАО|ОАО|ЗАО|АО|ООО)\)', ' ', name)
    name = re.sub(rf'(?<![А-Яа-яЁё]){LEGAL}(?![А-Яа-яЁё])', ' ', name)
    name = name.replace('"', ' ').replace('«', ' ').replace('»', ' ')
    name = re.sub(r'\s+', ' ', name).strip(' -,')
    if name.isupper():
        name = ' '.join(w if len(w) <= 3 and w.isalpha() and w not in ('БАНК',) else w.capitalize()
                        for w in name.split(' '))
        name = re.sub(r'-([а-яё])', lambda m: '-' + m[1].upper(), name)
    return name or official


def non_bank(reg, official):
    return reg.endswith('-К') or reg.endswith('-ЦК') or bool(
        re.search(r'(?<![А-Яа-я])(?:НКО|РНКО|НДКО|ЦК)(?![А-Яа-я])', official))


def parse_ed807(path):
    raw = Path(path).read_bytes()
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        names = [n for n in archive.namelist() if n.endswith('.xml')]
        if len(names) != 1:
            raise SystemExit('Expected one ED807 XML file')
        xml = archive.read(names[0])
    root = ET.fromstring(xml)
    ns = {'e': 'urn:cbr-ru:ed:v2.0'}
    if root.tag != '{urn:cbr-ru:ed:v2.0}ED807':
        raise SystemExit('Not an ED807 BIC directory')
    banks = {}
    for entry in root.findall('e:BICDirectoryEntry', ns):
        info = entry.find('e:ParticipantInfo', ns)
        if info is None or info.get('PtType') != '20' or not info.get('RegN'):
            continue
        reg = info.get('RegN')
        item = banks.setdefault(reg, {'regNumber': reg, 'officialName': info.get('NameP'),
                                      'city': info.get('Nnp') or '', 'bics': []})
        item['bics'].append(entry.get('BIC'))
    items = sorted(banks.values(), key=lambda b: (int(re.match(r'\d+', b['regNumber'])[0]), b['regNumber']))
    for item in items:
        item['bics'].sort()
    return {
        'source': SOURCE_URL,
        'sourceDescription': 'Bank of Russia BIC directory ED807, participants PtType=20 (credit organizations)',
        'archive': names[0],
        'archiveSha256': digest(raw),
        'xmlSha256': digest(xml),
        'edDate': root.get('EDDate'),
        'businessDay': root.get('BusinessDay'),
        'count': len(items),
        'items': items,
    }


def dart_string(value):
    return json.dumps(value, ensure_ascii=False).replace('$', r'\$')


def generate_dart(registry, manifest, raster):
    logos = {x['regNumber']: x for x in manifest.get('items', [])}
    rendered = {x['id']: x for x in raster.get('items', [])}
    regs = {x['regNumber'] for x in registry['items']}
    missing = sorted(set(BRANDS) - regs)
    if missing:
        raise SystemExit(f'Brand registration numbers absent from the registry: {missing}')
    lines = [
        '// GENERATED by tool/bank_catalog.py — do not edit by hand.',
        '// Credit organizations: Bank of Russia BIC directory ED807',
        f"// ({registry['source']}), business day {registry['businessDay']},",
        f"// archive SHA-256 {registry['archiveSha256']}.",
        '// Logo provenance: assets/banks/manifest.json, docs/BANKS.md.',
        "import 'service_catalog.dart';",
        '',
        'class RussianBank {',
        '  const RussianBank({',
        '    required this.regNumber,',
        '    required this.bics,',
        '    required this.officialName,',
        '    required this.name,',
        '    this.city = \'\',',
        '    this.aliases = const [],',
        '    this.nonBank = false,',
        '    this.logoAsset,',
        '    this.preserveColors = true,',
        '    this.background = 0xFFFFFFFF,',
        '    this.inset = .1,',
        '  });',
        '',
        '  /// Registration number in the Bank of Russia register (e.g. 1481, 3510-К).',
        '  final String regNumber;',
        '  final List<String> bics;',
        '  final String officialName, name, city;',
        '  final List<String> aliases;',
        '',
        '  /// Non-bank credit organization (НКО/РНКО), still a licensed institution.',
        '  final bool nonBank;',
        '',
        '  /// Original logo file; null means no verified original mark is bundled.',
        '  final String? logoAsset;',
        '  final bool preserveColors;',
        '  final int background;',
        '  final double inset;',
        '',
        "  String get id => 'bank_${regNumber.toLowerCase().replaceAll('к', 'k').replaceAll('ц', 'c').replaceAll(RegExp('[^0-9a-z]'), '')}';",
        "  String? get rasterAsset => logoAsset == null ? null : 'assets/banks/raster/$id.png';",
        '',
        '  SubscriptionService toService() => SubscriptionService(',
        '    id: id,',
        '    name: name,',
        "    group: 'banks',",
        '    aliases: [officialName, regNumber, ...bics, ...aliases],',
        '    assetPath: logoAsset,',
        '    rasterPath: rasterAsset,',
        '    preserveColors: preserveColors,',
        '    background: background,',
        '    inset: inset,',
        '  );',
        '}',
        '',
        'abstract final class BankCatalog {',
        f"  static const sourceUrl = {dart_string(registry['source'])};",
        f"  static const businessDay = {dart_string(registry['businessDay'])};",
        '  static const entries = <RussianBank>[',
    ]
    order = list(BRANDS)
    ranked = sorted(registry['items'], key=lambda x: (
        order.index(x['regNumber']) if x['regNumber'] in BRANDS else len(order),
        clean_name(x['officialName']).lower().replace('ё', 'е')))
    for item in ranked:
        reg = item['regNumber']
        brand = BRANDS.get(reg)
        name = brand[0] if brand else clean_name(item['officialName'])
        aliases = list(brand[1]) if brand else []
        cleaned = clean_name(item['officialName'])
        if cleaned != name and cleaned not in aliases:
            aliases.append(cleaned)
        logo = logos.get(reg)
        lines.append('    RussianBank(')
        lines.append(f'      regNumber: {dart_string(reg)},')
        lines.append(f"      bics: [{', '.join(dart_string(b) for b in item['bics'])}],")
        lines.append(f"      officialName: {dart_string(item['officialName'])},")
        lines.append(f'      name: {dart_string(name)},')
        if item.get('city'):
            lines.append(f"      city: {dart_string(item['city'])},")
        if aliases:
            lines.append(f"      aliases: [{', '.join(dart_string(a) for a in aliases)}],")
        if non_bank(reg, item['officialName']):
            lines.append('      nonBank: true,')
        if logo:
            if id_for(reg) not in rendered:
                raise SystemExit(f'Logo without PNG display copy: {reg}')
            lines.append(f"      logoAsset: {dart_string(logo['assetPath'])},")
            lines.append(f"      background: 0xFF{logo.get('background', '#FFFFFF').lstrip('#').upper()},")
            lines.append(f"      inset: {logo.get('inset', 0.1)},")
        lines.append('    ),')
    lines += ['  ];', HELPERS, '}', '']
    return '\n'.join(lines)


def validate_artwork(name, content):
    if not content or len(content) > MAX_BYTES:
        raise ValueError(f'Invalid artwork size: {name}')
    if name.endswith('.svg'):
        if b'<!ENTITY' in content.upper():
            raise ValueError(f'External XML declarations are not allowed: {name}')
        if ET.fromstring(content).tag.rsplit('}', 1)[-1] != 'svg':
            raise ValueError(f'Not SVG artwork: {name}')
    elif name.endswith('.png'):
        if not content.startswith(b'\x89PNG\r\n\x1a\n'):
            raise ValueError(f'Not PNG artwork: {name}')
        width, height = struct.unpack('>II', content[16:24])
        if not width or not height or width > 12000 or height > 12000:
            raise ValueError(f'Invalid image dimensions: {name}')
    elif name.endswith('.jpg'):
        if not content.startswith(b'\xff\xd8\xff'):
            raise ValueError(f'Not JPEG artwork: {name}')
    else:
        raise ValueError(f'Unsupported artwork type: {name}')


def commons(title):
    query = urllib.parse.urlencode({
        'action': 'query', 'titles': 'File:' + title, 'prop': 'imageinfo', 'format': 'json',
        'iiprop': 'url|mime|size|sha1|extmetadata|timestamp'})
    for attempt in range(8):
        try:
            time.sleep(4)
            with urllib.request.urlopen(urllib.request.Request(
                    'https://commons.wikimedia.org/w/api.php?' + query, headers=UA), timeout=60) as r:
                page = next(iter(json.load(r)['query']['pages'].values()))
                return page['imageinfo'][0]
        except urllib.error.HTTPError as error:
            if error.code != 429:
                raise
            time.sleep(30 * (attempt + 1))
    raise SystemExit('Commons rate limit')


def download(url, headers=UA):
    for attempt in range(8):
        try:
            time.sleep(3)
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as r:
                if urllib.parse.urlparse(r.url).scheme != 'https':
                    raise ValueError('Artwork redirected outside HTTPS')
                return r.read(MAX_BYTES + 1)
        except urllib.error.HTTPError as error:
            if error.code != 429:
                raise
            time.sleep(30 * (attempt + 1))
        except (urllib.error.URLError, ConnectionError):
            if attempt == 7:
                raise
            time.sleep(5)
    raise SystemExit('Download rate limit')


def fetch_logos():
    ASSETS.mkdir(parents=True, exist_ok=True)
    items = []
    for reg, spec in LOGOS.items():
        record = {'regNumber': reg, 'id': id_for(reg), 'brand': BRANDS[reg][0],
                  'background': spec.get('background', '#FFFFFF'), 'inset': spec.get('inset', 0.1),
                  'selection': spec['why'], 'sourceType': spec.get('sourceType', 'wikimedia-commons')}
        if record['sourceType'] in ('google-favicon-service', 'yandex-favicon-service'):
            content = download(spec['url'], BROWSER_UA)
            if digest(content) != spec['sha256']:
                raise SystemExit(f'Mirrored site icon changed since review: {reg}; review it again')
            kind = 'jpg' if content.startswith(b'\xff\xd8\xff') else 'png'
            path = ASSETS / f'{id_for(reg)}.{kind}'
            record.update({
                'source': spec['page'], 'downloadUrl': spec['url'],
                'mime': 'image/jpeg' if kind == 'jpg' else 'image/png',
                'license': {'LicenseShortName': 'Proprietary (bank website icon via favicon mirror)'},
                'rights': 'Site icon published by the bank\'s official website, as served by a public '
                          'favicon mirror; copyright and trademark belong to the bank. Used only to '
                          'identify the bank; no endorsement implied.',
            })
        elif record['sourceType'] == 'official-website':
            content = download(spec['url'], BROWSER_UA)
            if digest(content) != spec['sha256']:
                raise SystemExit(f'Official artwork changed since review: {reg}; review it again')
            kind = 'svg' if b'<svg' in content[:400] else 'png'
            path = ASSETS / f'{id_for(reg)}.{kind}'
            record.update({
                'source': spec['page'], 'downloadUrl': spec['url'],
                'mime': 'image/svg+xml' if kind == 'svg' else 'image/png',
                'license': {'LicenseShortName': 'Proprietary (official bank website asset)'},
                'rights': 'Exact file served by the bank\'s official website; copyright and trademark '
                          'belong to the bank. Used only to identify the bank; no endorsement implied.',
            })
        else:
            info = commons(spec['title'])
            content = download(info['url'])
            if hashlib.sha1(content).hexdigest() != info['sha1']:
                raise SystemExit(f'Commons SHA-1 mismatch: {reg}')
            suffix = Path(urllib.parse.urlparse(info['url']).path).suffix.lower()
            path = ASSETS / f'{id_for(reg)}{suffix}'
            meta = {k: v.get('value') for k, v in info.get('extmetadata', {}).items() if k in (
                'ImageDescription', 'Credit', 'Artist', 'LicenseShortName', 'UsageTerms',
                'AttributionRequired', 'Copyrighted', 'LicenseUrl', 'DateTimeOriginal')}
            record.update({
                'source': info['descriptionurl'], 'downloadUrl': info['url'], 'mime': info['mime'],
                'commonsSha1': info['sha1'], 'commonsTimestamp': info['timestamp'], 'license': meta,
                'rights': 'Original file bytes from Wikimedia Commons with the license stated there. '
                          'Trademark rights remain with the bank; no endorsement is implied.',
            })
        validate_artwork(path.name, content)
        path.write_bytes(content)
        record.update({'assetPath': str(path.relative_to(ROOT)), 'bytes': len(content),
                       'sha256': digest(content)})
        items.append(record)
    MANIFEST.write_text(json.dumps({'items': items}, ensure_ascii=False, indent=1) + '\n')
    print(f'Fetched {len(items)} original bank logos')


def render_svg(source, temp):
    document = ET.fromstring(source.read_bytes())
    viewbox = [float(x) for x in re.split(r'[ ,]+', document.get('viewBox', '').strip()) if x]

    def dimension(value):
        match = re.fullmatch(r'([0-9.]+)(?:px)?', value or '')
        return float(match[1]) if match else None
    width, height = dimension(document.get('width')), dimension(document.get('height'))
    if width is None or height is None:
        if len(viewbox) != 4 or min(viewbox[2:]) <= 0:
            raise ValueError(f'Missing bounded SVG page: {source.name}')
        width, height = viewbox[2:]
    pixels = max(1, round((SIZE - 2 * GUTTER) * width / max(width, height)))
    result = subprocess.run(['inkscape', str(source), '--export-type=png', '--export-area-page',
                             f'--export-filename={temp}', f'--export-width={pixels}'],
                            capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f'Inkscape failed for {source.name}: {result.stderr[-400:]}')
    from PIL import Image
    return Image.open(temp).convert('RGBA')


def render():
    from PIL import Image
    if not shutil.which('inkscape'):
        raise SystemExit('Inkscape is required for --render')
    manifest = json.loads(MANIFEST.read_text())
    RASTER.mkdir(parents=True, exist_ok=True)
    records = []
    with tempfile.TemporaryDirectory(prefix='finance-bank-raster-') as scratch:
        for item in manifest['items']:
            source = ROOT / item['assetPath']
            raw = source.read_bytes()
            if digest(raw) != item['sha256']:
                raise SystemExit(f'Original SHA mismatch: {item["id"]}')
            if source.suffix == '.svg':
                image = render_svg(source, Path(scratch) / 'render.png')
                operation = 'Inkscape SVG page rendered proportionally with transparent gutter; original colors unchanged'
            else:
                image = Image.open(io.BytesIO(raw)).convert('RGBA')
                scale = (SIZE - 2 * GUTTER) / max(image.size)
                image = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))),
                                     Image.Resampling.LANCZOS)
                operation = 'Original PNG proportionally resized (Lanczos) into transparent canvas; colors unchanged'
            square = Image.new('RGBA', (SIZE, SIZE))
            square.alpha_composite(image, ((SIZE - image.width) // 2, (SIZE - image.height) // 2))
            out = io.BytesIO()
            square.save(out, format='PNG', optimize=True)
            data = out.getvalue()
            target = RASTER / f'{item["id"]}.png'
            target.write_bytes(data)
            records.append({'id': item['id'], 'regNumber': item['regNumber'],
                            'assetPath': str(target.relative_to(ROOT)), 'sourceAssetPath': item['assetPath'],
                            'sourceSha256': item['sha256'], 'sha256': digest(data), 'bytes': len(data),
                            'width': SIZE, 'height': SIZE, 'operation': operation})
    renderer = subprocess.check_output(['inkscape', '--version'], text=True, stderr=subprocess.DEVNULL).strip()
    RASTER_MANIFEST.write_text(json.dumps({
        'renderer': renderer, 'sourceManifestSha256': digest(MANIFEST.read_bytes()),
        'canvas': SIZE, 'gutter': GUTTER, 'items': records}, ensure_ascii=False, indent=1) + '\n')
    print(f'Rendered {len(records)} PNG display copies')


def verify():
    from PIL import Image
    registry = json.loads(REGISTRY.read_text())
    manifest = json.loads(MANIFEST.read_text())
    raster = json.loads(RASTER_MANIFEST.read_text())
    assert registry['count'] == len(registry['items']) > 300, 'registry too small'
    regs = [x['regNumber'] for x in registry['items']]
    assert len(regs) == len(set(regs)), 'duplicate registration numbers'
    bics = [b for x in registry['items'] for b in x['bics']]
    assert len(bics) == len(set(bics)) and all(re.fullmatch(r'\d{9}', b) for b in bics), 'bad BIC'
    assert raster['sourceManifestSha256'] == digest(MANIFEST.read_bytes()), 'raster manifest is stale'
    rendered = {x['id']: x for x in raster['items']}
    assert set(rendered) == {x['id'] for x in manifest['items']}, 'logo/PNG sets differ'
    for item in manifest['items']:
        assert item['regNumber'] in regs, f'logo for unknown bank {item["regNumber"]}'
        assert item['downloadUrl'].startswith('https://'), item['id']
        assert item['sourceType'] in ('official-website', 'wikimedia-commons', 'google-favicon-service',
                                  'yandex-favicon-service'), item['id']
        assert item.get('license', {}).get('LicenseShortName'), f'missing license {item["id"]}'
        raw = (ROOT / item['assetPath']).read_bytes()
        validate_artwork(item['assetPath'], raw)
        assert digest(raw) == item['sha256'], f'original SHA mismatch {item["id"]}'
        png = rendered[item['id']]
        assert png['sourceSha256'] == item['sha256']
        data = (ROOT / png['assetPath']).read_bytes()
        assert digest(data) == png['sha256'], f'PNG SHA mismatch {item["id"]}'
        image = Image.open(io.BytesIO(data)).convert('RGBA')
        assert image.size == (SIZE, SIZE)
        assert image.getchannel('A').getextrema()[1] > 0, f'invisible PNG {item["id"]}'
    expected = generate_dart(registry, manifest, raster)

    def canonical(text):  # dart format only moves whitespace and commas
        return re.sub(r'[\s,]', '', text)
    if canonical(DART.read_text()) != canonical(expected):
        raise SystemExit('lib/domain/bank_catalog.dart differs from tool output; run --build')
    print(f'Verified {len(regs)} credit organizations ({len(bics)} BIC), '
          f'{len(manifest["items"])} original logos and PNG display copies')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--build', metavar='ED807_ZIP')
    mode.add_argument('--fetch-logos', action='store_true')
    mode.add_argument('--render', action='store_true')
    mode.add_argument('--generate', action='store_true', help='rewrite Dart from recorded JSON')
    mode.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    if args.build:
        registry = parse_ed807(args.build)
        ASSETS.mkdir(parents=True, exist_ok=True)
        REGISTRY.write_text(json.dumps(registry, ensure_ascii=False, indent=1) + '\n')
        args.generate = True
    if args.fetch_logos:
        fetch_logos()
    if args.render:
        render()
    if args.generate:
        manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {'items': []}
        raster = json.loads(RASTER_MANIFEST.read_text()) if RASTER_MANIFEST.exists() else {'items': []}
        DART.write_text(generate_dart(json.loads(REGISTRY.read_text()), manifest, raster))
        if shutil.which('dart'):
            subprocess.run(['dart', 'format', str(DART)], check=True, capture_output=True)
        print(f'Generated {DART.relative_to(ROOT)}')
    if args.verify:
        verify()


if __name__ == '__main__':
    sys.exit(main())

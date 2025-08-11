---Автор: Степанов Андрей
---Дата: 08.08.2025

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
---Всего объявлений проданной недвижимости в СПБ
    ---Задача 1. Время активности объявлений  
necessary_information AS (
SELECT  id,
		a.last_price / f.total_area AS square,     ---Квадратный метр стоимость
		f.total_area,                              ---Площадь
		rooms,                                     ---Комнаты
		balcony,						           ---Балконы
		floor,                                     ---Этаж
		ceiling_height,                            ---Высота потолка
		kitchen_area,                              ---Площадь кухни
		is_apartment,                              ---Апартамент или нет
		open_plan,                                 ---Открытая планеровка
		a.last_price,                              ---Цена 
		CASE 
			WHEN c.city = 'Санкт-Петербург'
				THEN 'Санкт-Петербург'
			ELSE 'ЛенОбласть'
		END	AS 	district,                ---В каком районе недвижимость
		CASE
			WHEN a.days_exposition IS NULL
				THEN 'Не продана'                  ---Для проверки не проданой недвижимости, можно перенести в секцию WHERE (a.days_exposition IS NOT NULL)
			WHEN a.days_exposition <=30
				THEN 'a.Меньше месяца'
			WHEN 30< a.days_exposition AND a.days_exposition <=90
				THEN 'b.Меньше квартала'
			WHEN 90< a.days_exposition AND a.days_exposition <=180
				THEN 'c.Меньше полугода'
			ELSE 'd.Больше полугода'
		END	AS period,	                 ---За какое время была продана недвижимость
		t.TYPE
FROM real_estate.flats AS f
JOIN real_estate.advertisement AS a USING(id)
JOIN real_estate.city AS c USING(city_id)
JOIN real_estate.TYPE AS t USING(type_id)
WHERE id IN (SELECT * FROM filtered_id) AND type = 'город'
)
SELECT  district,                                                                                ---Район СПБ или Область
		period,                                                                                  ---За какое время продана
		COUNT(id),                                                                               ---Кол-во проданной недвижимости
		ROUND(COUNT(id)::NUMERIC / (SELECT count(id) FILTER (WHERE period <> 'Не продана') FROM necessary_information), 3) AS count_share, ---Её доля от всех объявлений
		ROUND(AVG(total_area)::NUMERIC,2) AS avg_share,                                          ---Средняя площадь
		ROUND(AVG(last_price)::NUMERIC,2) AS avg_price,                                          ---Средняя цена квартиры
		ROUND(AVG(square)::NUMERIC) AS avg_cost_area,                                          ---Средняя стоимость кв'м 
		PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS median_rooms,                      ---Медиана комнат
		PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony) AS median_balcony,                  ---Медиана балконов
		PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY floor) AS median_floor,                      ---Медиана этажей
		PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY ceiling_height) AS median_ceiling_height,    ---Медиана высоты потолка
		ROUND(AVG(kitchen_area)::NUMERIC,2) AS square_kitchen_area,	                             ---Средняя площадь кухни
		ROUND((SELECT count(id) FILTER (WHERE is_apartment = 1 AND period <> 'Не продана') FROM necessary_information)::NUMERIC / count(id),2) AS share_apartment,   ---Доля апартаментов от общего числа
		ROUND((SELECT count(id) FILTER (WHERE open_plan = 1 AND period <> 'Не продана') FROM necessary_information)::NUMERIC / count(id),2) AS open_plan             ---Доля с открытой планировкой от общего
FROM necessary_information
WHERE period <> 'Не продана'
GROUP BY district, period
ORDER BY district DESC, period;


---Задача 2. Сезонность объявлений
  ---Первый способ через общее кол-во по месяцам
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
first_announcement AS (
	SELECT 
			COUNT(first_day_exposition) AS count_ann,                                               ---Кол-во открытых объявлений
			EXTRACT(month FROM first_day_exposition) AS month_op,
			AVG(a.last_price/f.total_area) AS avg_square_price,                                     ---Ср. цена за кв/м
			AVG(f.total_area) AS square                                                             ---Ср. площадь открытых
	FROM real_estate.advertisement AS a
	JOIN real_estate.flats AS f USING(id)
	WHERE id IN (SELECT * FROM filtered_id) AND EXTRACT(year FROM first_day_exposition)>2014        ---Выделяем полный год(за 2014 год данные начинаются с конца ноября, а за 2019 — заканчиваются в мае.)
                                     	    AND EXTRACT(year FROM first_day_exposition)<2019
	GROUP BY EXTRACT(month FROM first_day_exposition)
),
closing_announcement AS (
	SELECT  COUNT(a.days_exposition) AS count_clos,                                                   ---Кол-во закрытых объявлений
			EXTRACT(month FROM a.first_day_exposition + a.days_exposition::int) AS month_cl,
			ROUND(AVG(f.total_area)::NUMERIC, 2) AS avg_square_ex,                                    ---Ср. площадь закрытых  
	        ROUND(AVG(a.last_price/f.total_area::NUMERIC)) AS square_ex                               ---Ср. цена за кв/м закрытых
	FROM real_estate.advertisement AS a
	JOIN real_estate.flats AS f USING(id) 
	WHERE id IN (SELECT * FROM filtered_id) AND EXTRACT(year FROM first_day_exposition)>2014 
                                     		AND EXTRACT(year FROM first_day_exposition)<2019
                                    		AND days_exposition IS NOT NULL
    GROUP BY EXTRACT(month FROM first_day_exposition + days_exposition::int)
)
SELECT  CASE 
		WHEN month_op = 1  THEN 'Январь'
		WHEN month_op = 2  THEN 'Февраль'
		WHEN month_op = 3  THEN 'Март'
		WHEN month_op = 4  THEN 'Апрель'
		WHEN month_op = 5  THEN 'Май'
		WHEN month_op = 6  THEN 'Июнь'
		WHEN month_op = 7  THEN 'Июль'
		WHEN month_op = 8  THEN 'Август'
		WHEN month_op = 9  THEN 'Сентябрь'
		WHEN month_op = 10 THEN 'Октябрь'
		WHEN month_op = 11 THEN 'Нояберь'
		WHEN month_op = 12 THEN 'Декабрь' 
	END AS month,
		count_ann AS open_announ,                             ---Кол-во открытых объявлений по месяцам
		RANK() over(ORDER BY count_ann DESC) AS rank_open,
		CASE 
		WHEN month_op = 1  THEN 'Январь'
		WHEN month_op = 2  THEN 'Февраль'
		WHEN month_op = 3  THEN 'Март'
		WHEN month_op = 4  THEN 'Апрель'
		WHEN month_op = 5  THEN 'Май'
		WHEN month_op = 6  THEN 'Июнь'
		WHEN month_op = 7  THEN 'Июль'
		WHEN month_op = 8  THEN 'Август'
		WHEN month_op = 9  THEN 'Сентябрь'
		WHEN month_op = 10 THEN 'Октябрь'
		WHEN month_op = 11 THEN 'Нояберь'
		WHEN month_op = 12 THEN 'Декабрь' 
	END AS month,
		count_clos AS closing_announ,                           ---Кол-во закрытых объявлений по месяцам
		RANK() over(ORDER BY count_clos DESC) AS rank_closing,
		ROUND(avg_square_price::NUMERIC,2) AS avg_square_price_open,           ---Ср. цена за кв/м открытых
		ROUND(square::NUMERIC,2)  AS avg_square_open,                          ---Ср. площадь открытых
		ROUND(square_ex::NUMERIC,2) AS avg_square_price_clos,                  ---Ср. цена за кв/м закрытых
		ROUND(avg_square_ex::NUMERIC,2)  AS avg_square_clos                    ---Ср. площадь закрытых
FROM first_announcement
LEFT JOIN closing_announcement ON closing_announcement.month_cl = first_announcement.month_op
ORDER BY RANK() over(ORDER BY count_ann DESC);



---ВТОРОЙ СПОСОБ через среднее по месяцам
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
first_announcement AS (
	SELECT 
			COUNT(first_day_exposition) AS count_ann,                                             ---Кол-во объявлений
			EXTRACT(year FROM first_day_exposition) AS year,                                      ---Выделяет гол
			EXTRACT(month FROM first_day_exposition) AS month_op,                                 ---Выделяет месяц
			AVG(a.last_price/f.total_area) AS avg_square,                                         ---Ср. цена за кв/м
			AVG(total_area) AS square                                                               ---Ср. площадь
	FROM real_estate.advertisement AS a
	JOIN real_estate.flats AS f USING(id)
	WHERE id IN (SELECT * FROM filtered_id) AND EXTRACT(year FROM first_day_exposition)>2014               ------Выделяем полный год(за 2014 год данные начинаются с конца ноября, а за 2019 — заканчиваются в мае.)
                                     	    AND EXTRACT(year FROM first_day_exposition)<2019
	GROUP BY EXTRACT(YEAR FROM first_day_exposition), EXTRACT(month FROM first_day_exposition)
),
closing_announcement AS (
	SELECT  COUNT(days_exposition) AS count_clos,
        	EXTRACT(year FROM first_day_exposition + days_exposition::int) AS year,
			EXTRACT(month FROM first_day_exposition + days_exposition::int) AS month_cl,
			ROUND(AVG(f.total_area)::NUMERIC, 2) AS avg_square_ex,                                    ---Ср. площадь закрытых  
	        ROUND(AVG(a.last_price/f.total_area::NUMERIC)) AS square_ex                               ---Ср. цена за кв/м закрытых
	FROM real_estate.advertisement AS a
	JOIN real_estate.flats AS f USING(id)
	WHERE id IN (SELECT * FROM filtered_id) AND EXTRACT(year FROM first_day_exposition)>2014 
                                     		AND EXTRACT(year FROM first_day_exposition)<2019
                                    		AND days_exposition IS NOT NULL
    GROUP BY EXTRACT(year FROM first_day_exposition + days_exposition::int), EXTRACT(month FROM first_day_exposition + days_exposition::int)
)
SELECT  
		CASE 
		WHEN month_op = 1  THEN 'Январь'
		WHEN month_op = 2  THEN 'Февраль'
		WHEN month_op = 3  THEN 'Март'
		WHEN month_op = 4  THEN 'Апрель'
		WHEN month_op = 5  THEN 'Май'
		WHEN month_op = 6  THEN 'Июнь'
		WHEN month_op = 7  THEN 'Июль'
		WHEN month_op = 8  THEN 'Август'
		WHEN month_op = 9  THEN 'Сентябрь'
		WHEN month_op = 10 THEN 'Октябрь'
		WHEN month_op = 11 THEN 'Нояберь'
		WHEN month_op = 12 THEN 'Декабрь' 
	END AS month,
	DENSE_RANK () over(ORDER BY avg(count_ann) DESC) AS open_rank,          ---Ранг открытых объявлений
	ROUND(avg(count_ann)) AS open,                                                ---Среднее кол-во открытых обявлений по месяцам
	DENSE_RANK () over(ORDER BY avg(count_clos) DESC) AS closing_rank,      ---Ранг закрытых объявлений
	ROUND(avg(count_clos)) AS closing,                                            ---Среднее кол-во закрытых обявлений по месяцам
	ROUND(AVG(f.avg_square)::NUMERIC,2) AS avg_price_square,                ---Ср. цена за кв/м открытых
	ROUND(AVG(square)::NUMERIC,2) AS avg_square,                            ---Ср. площадь открытых
	ROUND(AVG(square_ex)::NUMERIC,2) AS avg_square_price_clos,              ---Ср. цена за кв/м закрытых
	ROUND(AVG(avg_square_ex)::NUMERIC,2)  AS avg_square_clos                ---Ср. площадь закрытых
FROM first_announcement AS f 
JOIN closing_announcement AS c ON f.month_op = c.month_cl
GROUP BY month_op, month_cl;


---Задача 3. Анализ рынка недвижимости Ленобласти

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
len_obl AS (
SELECT  c.city,                                                                  ---Город
		COUNT(f.id) AS count_announcements,                                      ---Кол-во объявлений
		COUNT(a.days_exposition) AS clos_announ,                                 ---Кол-во закрытых объявлений
		ROUND(AVG(a.last_price)::NUMERIC,2) AS avg_price,                        ---Ср. цена за недвижимость
		ROUND(AVG(a.last_price/f.total_area)::NUMERIC,2) AS avg_price_square,    ---Ср. цена за кв/м
		ROUND(AVG(f.total_area)::NUMERIC,2) AS avg_area,                         ---Ср. площадь
		PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER by f.rooms) AS  median_rooms,    ---Медиана комнат
		PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY f.floor) AS 	median_floor,    ---Медиана этажа
		ROUND(AVG(a.days_exposition)::NUMERIC) AS avg_time_sale,                 ---Ср. время продажи
		ROUND(COUNT(a.days_exposition) / COUNT(f.id)::NUMERIC,2)*100 AS percent  ---Процент закрытых объявлений
FROM real_estate.flats AS f
JOIN real_estate.city AS c USING(city_id)
JOIN real_estate.advertisement AS a USING(id)
WHERE id IN (SELECT * FROM filtered_id) AND c.city <> 'Санкт-Петербург' 
GROUP BY c.city
ORDER BY count_announcements DESC
)
SELECT *
FROM len_obl
WHERE percent>80 AND clos_announ>100;       ---Фильтр процент продаж больше 80% и кол-во продаж больше 100






